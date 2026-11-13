// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import Foundation

#if os(iOS)
  import UIKit
#endif

/// Something just done that the Undo toast can take back.
struct Undoable: Identifiable {
  enum Kind {
    /// Mark all as read (see `PendingMarkAll`).
    case markAll
    /// Items marked read as they scrolled off the top of the list.
    case scrolled
  }

  let id = UUID()
  let kind: Kind
  let message: String
}

/// Mark all as read, done here but not sent yet: it waits until the toast
/// goes, so Undo needs nothing from the server (which can't mark a feed
/// unread again). What the lists showed before, to put back on Undo.
struct PendingMarkAll {
  /// The feeds to mark read on the server.
  let feeds: [String]
  /// Their unread counts before.
  let unread: [String: Int]
  /// The items in the lists that were unread.
  let items: Set<Int64>
  let queue: [Item]
  let latestUnread: [Item]
}

/// The Undo toast: a few seconds to take back marking items read in bulk.
extension Store {
  /// How long the toast stays.
  static let undoSeconds = 6

  /// Shows the toast, replacing any other: what that one offered stands.
  func offerUndo(_ kind: Undoable.Kind, _ message: String) {
    if let shown = undoable, shown.kind != kind { settle(shown.kind) }
    undoable = Undoable(kind: kind, message: message)
    undoTimer?.cancel()
    undoTimer = Task { [weak self] in
      try? await Task.sleep(for: .seconds(Self.undoSeconds))
      guard !Task.isCancelled else { return }
      self?.dismissUndo()
    }
  }

  /// The toast goes without Undo: what it offered stands.
  func dismissUndo() {
    guard let shown = undoable else { return }
    hideUndo()
    settle(shown.kind)
  }

  /// Takes back what the toast offers.
  func undo() async {
    guard let shown = undoable else { return }
    hideUndo()
    haptic(.undo)
    switch shown.kind {
    case .scrolled:
      let ids = scrolledRead
      scrolledRead = []
      for id in ids {
        if let item = self.item(id) { await setRead(item, false) }
      }
    case .markAll:
      cancelMarkAll()
    }
  }

  /// Going to the background, where the toast won't be seen: what it offers
  /// stands now. Mark all as read is sent while iOS still lets the app run.
  func dismissUndoForBackground() {
    #if os(iOS)
      guard pendingMarkAll != nil else {
        dismissUndo()
        return
      }
      hideUndo()
      scrolledRead = []
      let task = UIApplication.shared.beginBackgroundTask(withName: "Mark all as read")
      Task {
        await commitMarkAll(thenReload: false)
        UIApplication.shared.endBackgroundTask(task)
      }
    #else
      dismissUndo()
    #endif
  }

  /// Marks an item read that scrolled off the top of the list, offering
  /// Undo for every one since the toast last went.
  func markReadScrolledPast(_ item: Item) async {
    guard !item.read else { return }
    await setRead(item, true)
    scrolledRead.append(item.id)
    let count = scrolledRead.count
    offerUndo(.scrolled, count == 1 ? "Marked 1 item as read" : "Marked \(count) items as read")
  }

  func hideUndo() {
    undoTimer?.cancel()
    undoTimer = nil
    undoable = nil
  }

  private func settle(_ kind: Undoable.Kind) {
    switch kind {
    case .scrolled: scrolledRead = []
    case .markAll: Task { await commitMarkAll() }
    }
  }
}
