// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import Foundation

/// What the widgets show, and what they open.
extension Store {
  /// Writes what the widgets show, a moment after the last change (one action
  /// can change several things).
  func updateWidgets() {
    widgetUpdate?.cancel()
    widgetUpdate = Task {
      try? await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled else { return }
      WidgetStore.save(widgetSnapshot())
    }
  }

  private func widgetSnapshot() -> WidgetSnapshot {
    let entry = { (item: Item) in
      WidgetSnapshot.Entry(
        id: item.id, title: item.title, feed: self.feedTitle(item.feedId),
        published: item.published)
    }
    var snapshot = WidgetSnapshot()
    snapshot.configured = isConfigured
    snapshot.unread = totalUnread
    snapshot.latest = latestUnread.filter { !$0.read }.map(entry)
    if let item = playback.item {
      snapshot.nowPlaying = entry(item)
      snapshot.isPlaying = playback.isPlaying
      snapshot.position = playback.position
      snapshot.duration = playback.duration
      snapshot.rate = playback.rate
    }
    snapshot.hasQueue = hasQueue
    snapshot.upNext = queue.filter { $0.id != playback.item?.id }.prefix(4).map(entry)
    snapshot.written = Date()
    return snapshot
  }

  /// The widget's button: pauses or resumes, or plays the first in Up Next.
  func togglePlayback() async {
    if playback.item != nil {
      playback.togglePause()
    } else if let next = queue.first {
      await playback.play(next)
    }
  }

  /// Shows an item a widget opened, fetching it if no list here has it.
  func reveal(_ id: Int64) async {
    if item(id) == nil {
      await run {
        let full = try await api.item(id)
        articles[id] = full
      }
    }
    if source == nil { source = .all }
  }
}
