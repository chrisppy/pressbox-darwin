// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import Foundation
import Testing

@testable import Pressbox

// The app's logic that can be tested without its screens or a server: the
// offline outbox, downloads' bookkeeping, what makes the widgets redraw, the
// API's JSON, and time formatting.
//
// Two ways to run them: `just test` builds Core/ as a Swift package (Linux or
// Mac, no Xcode), and `just test-app` runs them in the iOS simulator.

/// An item decoded the way the API client decodes one.
private func item(
  id: Int64 = 1, read: Bool = false, enclosures: String = "[]", media: Bool = true
) throws -> Item {
  let mediaJSON = media ? #","media":{"enclosures":\#(enclosures)}"# : ""
  let json = #"""
    {"id":\#(id),"feed_id":"news","title":"Episode \#(id)","url":null,"author":null,
     "summary":null,"published":0,"read":\#(read),"starred":false\#(mediaJSON)}
    """#
  return try APIClient.decoder.decode(Item.self, from: Data(json.utf8))
}

struct OutboxTests {
  @Test func keepsOnlyTheLatestChangeOfEachKind() {
    var outbox = Outbox()
    #expect(outbox.isEmpty)
    outbox.add(.position(1, 15))
    outbox.add(.position(1, 30))
    outbox.add(.read(1, true))
    outbox.add(.read(2, false))
    #expect(outbox.positions == [1: 30])
    #expect(outbox.read == [1: true, 2: false])
    #expect(outbox.changes.count == 3)
  }

  @Test func sendsTheQueueLast() {
    var outbox = Outbox()
    outbox.add(.queue([3, 1]))
    outbox.add(.read(1, true))
    outbox.add(.starred(2, true))
    #expect(outbox.changes.last == .queue([3, 1]))
  }

  @Test func supersedeForgetsOnlyThatItemAndKind() {
    var outbox = Outbox()
    outbox.add(.read(1, true))
    outbox.add(.starred(1, true))
    outbox.supersede(with: .read(1, false))
    #expect(outbox.read.isEmpty)
    #expect(outbox.starred == [1: true])
  }

  @Test func removeLeavesANewerChange() {
    var outbox = Outbox()
    outbox.add(.position(1, 10))
    // Sent 10, and meanwhile 20 was kept: 20 still has to go.
    outbox.add(.position(1, 20))
    outbox.remove(.position(1, 10))
    #expect(outbox.positions == [1: 20])
    outbox.remove(.position(1, 20))
    #expect(outbox.isEmpty)
  }

  @Test func roundTripsThroughJSON() throws {
    var outbox = Outbox()
    outbox.add(.read(1, true))
    outbox.add(.queue([2]))
    let data = try JSONEncoder().encode(outbox)
    #expect(try JSONDecoder().decode(Outbox.self, from: data) == outbox)
    // Older files have no queue.
    let old = try JSONDecoder().decode(
      Outbox.self, from: Data(#"{"read":[],"starred":[],"positions":[]}"#.utf8))
    #expect(old.isEmpty)
  }
}

struct DownloadTests {
  @Test func taskInfoSurvivesItsDescription() {
    let info = TaskInfo(id: 42, kind: .video, automatic: true, ext: "mp4")
    #expect(TaskInfo(info.description) == info)
    #expect(info.file == "42-video.mp4")
    #expect(TaskInfo("not a task") == nil)
    #expect(TaskInfo(nil) == nil)
  }

  @Test func picksTheAudioAndSkipsStreams() throws {
    let episode = try item(
      enclosures: #"""
        [{"url":"https://x/live.m3u8","mime":"application/x-mpegURL"},
         {"url":"https://x/ep.mp4","mime":"video/mp4"},
         {"url":"https://x/ep.mp3","mime":"audio/mpeg"}]
        """#)
    #expect(DownloadFiles.enclosure(of: episode, video: false)?.url == "https://x/ep.mp3")
    #expect(DownloadFiles.enclosure(of: episode, video: true)?.url == "https://x/ep.mp4")
  }

  @Test func aStreamOnlyEpisodeCantBeDownloaded() throws {
    let stream = try item(
      enclosures: #"[{"url":"https://x/live.m3u8","mime":"application/vnd.apple.mpegurl"}]"#)
    #expect(DownloadFiles.enclosure(of: stream, video: false) == nil)
    #expect(DownloadFiles.enclosure(of: try item(media: false), video: false) == nil)
  }

  @Test(arguments: [
    ("https://x/a.mp3", "audio/mpeg", "mp3"),
    ("https://x/a.M4A?token=1", nil, "m4a"),
    ("https://x/download", "audio/mp4", "m4a"),
    ("https://x/download", "video/mp4", "mp4"),
    ("https://x/download", nil, "mp3"),
    ("https://x/a.longext", "audio/ogg", "ogg"),
  ])
  func fileExtensions(url: String, mime: String?, expected: String) throws {
    let mimeJSON = mime.map { #""\#($0)""# } ?? "null"
    let enclosure = try APIClient.decoder.decode(
      Enclosure.self, from: Data(#"{"url":"\#(url)","mime":\#(mimeJSON)}"#.utf8))
    #expect(DownloadFiles.fileExtension(of: enclosure) == expected)
  }
}

// The widgets' code is in the app, not in Core, so these run only in Xcode.
#if !SWIFT_PACKAGE
  struct WidgetTests {
    private let entry = WidgetSnapshot.Entry(id: 1, title: "One", feed: "News", published: 0)

    @Test func unreadChangesRedrawTheUnreadWidget() {
      let old = WidgetSnapshot()
      var new = old
      #expect(!WidgetStore.unreadChanged(old, new))
      new.unread = 3
      #expect(WidgetStore.unreadChanged(old, new))
      #expect(!WidgetStore.playingChanged(old, new), "the Up Next widget needn't redraw")
    }

    @Test func positionOnlyMattersWhilePaused() {
      var playing = WidgetSnapshot()
      playing.nowPlaying = entry
      playing.isPlaying = true
      var later = playing
      later.position = 120
      // Playing, the widget's bar moves by itself.
      #expect(!WidgetStore.playingChanged(playing, later))
      later.isPlaying = false
      #expect(WidgetStore.playingChanged(playing, later))
    }

    @Test func linksOpenItems() {
      #expect(WidgetStore.itemID(in: WidgetStore.link(1234)) == 1234)
      #expect(WidgetStore.itemID(in: URL(string: "https://example.com/item/1")!) == nil)
      #expect(WidgetStore.itemID(in: URL(string: "pressbox://feed/1")!) == nil)
    }
  }
#endif

struct ModelTests {
  @Test func decodesAnEpisode() throws {
    let episode = try item(
      id: 7, read: true,
      enclosures: #"[{"url":"https://x/e.mp3","mime":"audio/mpeg","length":1000}]"#)
    #expect(episode.id == 7)
    #expect(episode.read)
    #expect(episode.isEpisode)
    #expect(episode.resumeAt == 0, "no position means the start")
    #expect(episode.media?.audio?.length == 1000)
    #expect(episode.media?.video == nil)
  }

  @Test func anArticleIsntAnEpisode() throws {
    #expect(try !item(media: false).isEpisode)
  }
}

struct FormatTimeTests {
  @Test(arguments: [
    (0.0, "0:00"), (59.9, "0:59"), (61, "1:01"), (3600, "1:00:00"), (3725, "1:02:05"),
    (-5, "0:00"), (Double.nan, "0:00"),
  ])
  func formats(seconds: Double, expected: String) {
    #expect(formatTime(seconds) == expected)
  }
}
