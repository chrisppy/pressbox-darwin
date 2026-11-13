// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import Foundation

/// Which items the lists show: news (items without media), podcast
/// episodes, or both. Never neither: turning one off when the other is off
/// turns the other on.
struct Shows: Codable, Equatable {
  var news = true
  var podcasts = true

  var isBoth: Bool { news && podcasts }

  /// The `media` filter for the server's item lists: `nil` for both.
  var media: Bool? { isBoth ? nil : podcasts }

  mutating func set(news value: Bool) {
    news = value
    if !news && !podcasts { podcasts = true }
  }

  mutating func set(podcasts value: Bool) {
    podcasts = value
    if !news && !podcasts { news = true }
  }
}

extension Feed {
  /// The server counts each feed's episodes (2026.11 on), so podcasts can be
  /// told from news.
  var countsEpisodes: Bool { episodes != nil }

  var hasEpisodes: Bool { (episodes ?? 0) > 0 }

  /// Has items without media. A feed with no items yet counts as news.
  var hasNews: Bool {
    guard let episodes else { return true }
    return total > episodes || total == 0
  }

  /// Has items of a kind shown. A mixed feed is in both.
  func isShown(in shows: Shows) -> Bool {
    !countsEpisodes || (shows.news && hasNews) || (shows.podcasts && hasEpisodes)
  }

  /// Unread items of the kinds shown.
  func unread(in shows: Shows) -> Int {
    guard let unreadEpisodes else { return unread }
    return (shows.news ? max(0, unread - unreadEpisodes) : 0)
      + (shows.podcasts ? unreadEpisodes : 0)
  }
}

/// Body of `POST /api/v1/items/read-all`: the filters of the list to mark
/// read.
struct MarkRead: Codable, Equatable {
  var feed: String?
  var tag: String?
  var unread = true
  var media: Bool?

  init(source: Source, media: Bool?) {
    switch source {
    case .feed(let id): feed = id
    case .tag(let tag): self.tag = tag
    case .all, .starred: break
    }
    self.media = media
  }
}
