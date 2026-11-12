// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import Foundation

// JSON shapes of the pressbox API (see crates/pressbox-api). Timestamps are
// Unix seconds.

struct Feed: Codable, Identifiable, Hashable {
  let id: String
  let title: String
  let url: String
  let siteUrl: String?
  let tags: [String]
  var unread: Int
  let total: Int
  let lastFetched: Int64?
  let lastError: String?
  /// Removed from the server config but kept for its starred items.
  let archived: Bool?
  /// The feed's artwork.
  let image: String?
  /// `podcast:medium`: `podcast`, `music`, `video`, ...
  let medium: String?

  var isArchived: Bool { archived ?? false }
}

struct Item: Codable, Identifiable, Hashable {
  let id: Int64
  let feedId: String
  let title: String
  let url: String?
  let author: String?
  let summary: String?
  var content: String?
  let published: Int64
  var read: Bool
  var starred: Bool
  /// Audio or video (a podcast episode), if any.
  let media: Media?
  /// Where this user stopped playing it, in seconds; absent when 0.
  var position: Int?

  var publishedDate: Date { Date(timeIntervalSince1970: TimeInterval(published)) }
  var link: URL? { url.flatMap(URL.init(string:)) }
  var isEpisode: Bool { media != nil }
  var resumeAt: Int { position ?? 0 }
}

/// An item's audio and video, from its enclosures and the Podcasting 2.0
/// tags.
struct Media: Codable, Hashable {
  /// The feed's own enclosure first, then `podcast:alternateEnclosure`s.
  let enclosures: [Enclosure]
  /// Seconds.
  let duration: Int?
  let image: String?
  let season: Int?
  let episode: Int?
  /// The chapters file; read it through `APIClient.chapters`.
  let chapters: String?
  let transcripts: [TranscriptFile]?

  var video: Enclosure? { enclosures.first(where: \.isVideo) }
  /// The first that isn't video, else the video.
  var audio: Enclosure? { enclosures.first { !$0.isVideo } ?? video }
  var hasTranscript: Bool { !(transcripts ?? []).isEmpty }
}

struct Enclosure: Codable, Hashable {
  let url: String
  let mime: String?
  let length: Int64?
  let bitrate: Int?
  let height: Int?
  let title: String?

  var isVideo: Bool { mime?.hasPrefix("video/") ?? false }
}

struct TranscriptFile: Codable, Hashable {
  let url: String
  let mime: String
  let lang: String?
  let rel: String?
}

/// Body of `PUT /api/v1/items/{id}/position`.
/// `GET /api/v1/queue`: the Up Next queue.
struct Queue: Codable {
  let items: [Item]
}

/// Body for `PUT /api/v1/queue`: the whole queue, in order.
struct QueueOrder: Codable {
  let ids: [Int64]
}

struct Position: Codable {
  let position: Int
}

/// `GET /api/v1/items/{id}/chapters`.
struct Chapters: Codable {
  let chapters: [Chapter]
}

struct Chapter: Codable, Hashable, Identifiable {
  /// Seconds from the start.
  let start: Double
  let end: Double?
  let title: String?
  let image: String?
  let url: String?
  /// Only changes the artwork; left out of chapter lists.
  let hidden: Bool?

  var id: Double { start }
  var isHidden: Bool { hidden ?? false }
}

/// `GET /api/v1/items/{id}/transcript`.
struct Transcript: Codable {
  let segments: [Segment]
}

struct Segment: Codable, Hashable, Identifiable {
  let start: Double
  let end: Double
  let speaker: String?
  let text: String

  var id: Double { start }
}

struct ItemPage: Codable {
  let items: [Item]
  let nextCursor: String?
  /// Only from servers too old to give cursors.
  let nextOffset: Int?

  var next: NextPage? { nextCursor.map(NextPage.cursor) ?? nextOffset.map(NextPage.offset) }
}

/// Where the next page of items starts.
enum NextPage: Equatable {
  case cursor(String)
  case offset(Int)
}

struct Flag: Codable {
  let value: Bool
}

struct Updated: Codable {
  let updated: Int
}

struct PairRequest: Codable {
  let name: String
}

struct PairStart: Codable {
  let code: String
  let pollId: String
  let expiresIn: Int
}

struct PairApproved: Codable {
  let token: String
  let name: String
}

struct PendingPairing: Codable, Identifiable {
  let code: String
  let name: String
  let requested: Int64

  var id: String { code }
}

struct ApproveRequest: Codable {
  let user: String?
}

struct Approved: Codable {
  let name: String
  let user: String
}

/// Who this device's token belongs to.
/// `GET /api/v1/version`.
struct ServerVersion: Codable {
  let version: String
  let api: Int
}

struct Me: Codable {
  let user: String
  let admin: Bool
  let device: String?
}

/// What the item list shows.
enum Source: Hashable, Codable {
  case all
  case starred
  case feed(String)
  /// Every feed with this tag (the server's `tags`, or folders from OPML).
  case tag(String)
}
