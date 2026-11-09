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

  var publishedDate: Date { Date(timeIntervalSince1970: TimeInterval(published)) }
  var link: URL? { url.flatMap(URL.init(string:)) }
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
