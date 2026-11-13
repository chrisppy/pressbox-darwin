// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import Foundation
import WidgetKit

/// What the widgets show. The app writes it into the App Group container
/// whenever it changes; the widget extension only reads it, so widgets
/// need neither the token nor the network.
struct WidgetSnapshot: Codable, Equatable {
  struct Entry: Codable, Equatable, Hashable, Identifiable {
    let id: Int64
    let title: String
    let feed: String
    /// Unix seconds.
    let published: Int64
  }

  /// Paired with a server; otherwise the widgets say to open the app.
  var configured = false
  var unread = 0
  /// The newest unread items, newest first.
  var latest: [Entry] = []

  /// The episode playing or paused, if any.
  var nowPlaying: Entry?
  var isPlaying = false
  /// Seconds into `nowPlaying`, when this was written.
  var position: Double = 0
  var duration: Double?
  var rate: Float = 1
  /// When this was written, to work out where playback has got to since.
  var written = Date.distantPast

  /// The server keeps an Up Next queue.
  var hasQueue = false
  /// Up Next, without the episode playing.
  var upNext: [Entry] = []
}

enum WidgetStore {
  static let appGroup = "group.org.red-oxide.pressbox"

  /// The widgets' kinds, for reloading one at a time.
  static let unreadKind = "Unread"
  static let upNextKind = "UpNext"

  private static var url: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
      .appending(path: "widgets.json")
  }

  static func load() -> WidgetSnapshot {
    guard let url, let data = try? Data(contentsOf: url),
      let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    else { return WidgetSnapshot() }
    return snapshot
  }

  /// Saves the snapshot and has the widgets redraw, if anything they show
  /// changed.
  static func save(_ snapshot: WidgetSnapshot) {
    let old = load()
    var unchanged = snapshot
    unchanged.written = old.written
    guard unchanged != old, let url else { return }
    // Not completeFileProtection: widgets draw while the device is locked.
    guard let data = try? JSONEncoder().encode(snapshot),
      (try? data.write(to: url, options: .atomic)) != nil
    else { return }
    if unreadChanged(old, snapshot) {
      WidgetCenter.shared.reloadTimelines(ofKind: unreadKind)
    }
    if playingChanged(old, snapshot) {
      WidgetCenter.shared.reloadTimelines(ofKind: upNextKind)
    }
  }

  static func unreadChanged(_ a: WidgetSnapshot, _ b: WidgetSnapshot) -> Bool {
    a.configured != b.configured || a.unread != b.unread || a.latest != b.latest
  }

  static func playingChanged(_ a: WidgetSnapshot, _ b: WidgetSnapshot) -> Bool {
    a.configured != b.configured || a.nowPlaying != b.nowPlaying || a.isPlaying != b.isPlaying
      || a.rate != b.rate || a.hasQueue != b.hasQueue || a.upNext != b.upNext
      // Paused somewhere else: the progress bar moves.
      || (!b.isPlaying && a.position != b.position)
  }

  /// Opens an item in the app: `pressbox://item/123`.
  static func link(_ id: Int64) -> URL {
    URL(string: "pressbox://item/\(id)")!
  }

  /// The item id in a link from a widget.
  static func itemID(in url: URL) -> Int64? {
    guard url.scheme == "pressbox", url.host() == "item" else { return nil }
    return Int64(url.lastPathComponent)
  }
}
