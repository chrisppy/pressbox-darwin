// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import Foundation

/// A change to an item that is sent to the server.
enum Change: Equatable {
  case read(Int64, Bool)
  case starred(Int64, Bool)
  case position(Int64, Int)
  /// The whole Up Next queue, in order.
  case queue([Int64])
}

/// Changes made while the server couldn't be reached, kept on disk and sent
/// when it can be (see `Store.flushOutbox`). For each item only the latest
/// change of each kind is kept: marking an episode read twice, or saving its
/// position every 15 seconds while offline, leaves one change to send.
struct Outbox: Codable, Equatable {
  var read: [Int64: Bool] = [:]
  var starred: [Int64: Bool] = [:]
  var positions: [Int64: Int] = [:]
  /// The latest Up Next queue, sent after the rest: the server takes items
  /// marked read out of it.
  var queue: [Int64]?

  var isEmpty: Bool { read.isEmpty && starred.isEmpty && positions.isEmpty && queue == nil }

  var changes: [Change] {
    read.map { .read($0.key, $0.value) }
      + starred.map { .starred($0.key, $0.value) }
      + positions.map { .position($0.key, $0.value) }
      + (queue.map { [Change.queue($0)] } ?? [])
  }

  /// Keeps `change` to send later, replacing any earlier one of its kind.
  mutating func add(_ change: Change) {
    switch change {
    case .read(let id, let value): read[id] = value
    case .starred(let id, let value): starred[id] = value
    case .position(let id, let value): positions[id] = value
    case .queue(let ids): queue = ids
    }
  }

  /// Forgets any kept change of the same kind for the same item: `change`
  /// replaces it.
  mutating func supersede(with change: Change) {
    switch change {
    case .read(let id, _): read[id] = nil
    case .starred(let id, _): starred[id] = nil
    case .position(let id, _): positions[id] = nil
    case .queue: queue = nil
    }
  }

  /// Forgets `change` once it has been sent, unless a newer one of its kind
  /// was kept meanwhile.
  mutating func remove(_ change: Change) {
    if changes.contains(change) { supersede(with: change) }
  }
}

extension APIClient {
  func submit(_ change: Change) async throws {
    switch change {
    case .read(let id, let value): try await setRead(id, value)
    case .starred(let id, let value): try await setStarred(id, value)
    case .position(let id, let value): try await setPosition(id, value)
    case .queue(let ids): try await setQueue(ids)
    }
  }
}
