// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import Foundation

/// Up Next: the queue of episodes the server keeps.
extension Store {
  func loadQueue() async throws {
    do {
      queue = try await api.queue()
      hasQueue = true
    } catch APIError.notFound {
      // An older server, without a queue.
      queue = []
      hasQueue = false
    }
  }

  func isQueued(_ item: Item) -> Bool { queue.contains { $0.id == item.id } }

  /// Adds an episode to Up Next: to play next, or after the rest. Moves it
  /// there if it is queued already.
  func enqueue(_ item: Item, next: Bool = false) async {
    var new = queue.filter { $0.id != item.id }
    if next { new.insert(item, at: 0) } else { new.append(item) }
    await setQueue(new)
  }

  func dequeue(_ item: Item) async {
    await setQueue(queue.filter { $0.id != item.id })
  }

  /// Replaces Up Next (to reorder it, say): here at once, and on the server
  /// as soon as it can be reached.
  func setQueue(_ new: [Item]) async {
    let old = queue
    queue = new
    saveCache()
    updateWidgets()
    if !(await send(.queue(new.map(\.id)))) {
      queue = old
      saveCache()
    }
  }
}
