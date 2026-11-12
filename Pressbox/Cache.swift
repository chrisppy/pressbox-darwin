// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import Foundation

/// What the app last saw, kept on disk so it opens instantly and can be read
/// offline: the feed list, the last item list, and full articles that were
/// opened or prefetched.
struct Snapshot: Codable {
  var feeds: [Feed] = []
  var items: [Item] = []
  var articles: [Int64: Item] = [:]
}

enum Cache {
  /// Most full articles kept; the oldest are dropped first.
  static let maxArticles = 300

  private static var url: URL? { file("pressbox-cache.json") }
  private static var outboxURL: URL? { file("pressbox-outbox.json") }

  private static func file(_ name: String) -> URL? {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
      .appendingPathComponent(name)
  }

  static func load() -> Snapshot? {
    guard let url, let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(Snapshot.self, from: data)
  }

  static func save(_ snapshot: Snapshot) {
    guard let url else { return }
    var snapshot = snapshot
    if snapshot.articles.count > maxArticles {
      let keep = snapshot.articles.values
        .sorted { $0.published > $1.published }
        .prefix(maxArticles)
      snapshot.articles = Dictionary(uniqueKeysWithValues: keep.map { ($0.id, $0) })
    }
    write(snapshot, to: url)
  }

  /// Changes not sent to the server yet, kept apart from the snapshot so they
  /// survive it being cleared or failing to load.
  static func loadOutbox() -> Outbox {
    guard let outboxURL, let data = try? Data(contentsOf: outboxURL) else { return Outbox() }
    return (try? JSONDecoder().decode(Outbox.self, from: data)) ?? Outbox()
  }

  static func saveOutbox(_ outbox: Outbox) {
    guard let outboxURL else { return }
    if outbox.isEmpty {
      try? FileManager.default.removeItem(at: outboxURL)
    } else {
      write(outbox, to: outboxURL)
    }
  }

  private static func write(_ value: some Encodable & Sendable, to url: URL) {
    Task.detached(priority: .utility) {
      do {
        try FileManager.default.createDirectory(
          at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(value)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
      } catch {
        // A cache that fails to save is not worth bothering the user about.
      }
    }
  }

  /// Forgets everything, including unsent changes (signing out).
  static func clear() {
    for url in [url, outboxURL].compactMap({ $0 }) {
      try? FileManager.default.removeItem(at: url)
    }
  }
}
