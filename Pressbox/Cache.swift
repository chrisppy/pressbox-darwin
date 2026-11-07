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

  private static var url: URL? {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
      .appendingPathComponent("pressbox-cache.json")
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
    Task.detached(priority: .utility) {
      do {
        try FileManager.default.createDirectory(
          at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
      } catch {
        // A cache that fails to save is not worth bothering the user about.
      }
    }
  }

  static func clear() {
    guard let url else { return }
    try? FileManager.default.removeItem(at: url)
  }
}
