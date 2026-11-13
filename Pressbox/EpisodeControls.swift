// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import SwiftUI

// An episode's controls in its article's bottom bar: Play, Up Next,
// Download, and what its More menu offers.

/// The extras an episode's More menu offers: watch the video, its chapters,
/// its transcript; each only when the episode has one.
struct EpisodeExtras: View {
  @Environment(Store.self) private var store
  let item: Item
  @Binding var showChapters: Bool
  @Binding var showTranscript: Bool

  var body: some View {
    let playback = store.playback
    let media = item.media
    let playingVideo = playback.isCurrent(item) && playback.isVideo
    // With the video downloaded, Play already plays it.
    if media?.video != nil && !Playback.downloadedVideo(item) {
      Button(
        playingVideo && playback.isPlaying ? "Pause Video" : "Watch Video",
        systemImage: playingVideo && playback.isPlaying ? "pause.fill" : "play.rectangle"
      ) {
        Task { await playback.play(store.item(item.id) ?? item, video: true) }
      }
    }
    if media?.chapters != nil {
      Button("Chapters", systemImage: "list.bullet") { showChapters = true }
    }
    if media?.hasTranscript ?? false {
      Button("Transcript", systemImage: "text.quote") { showTranscript = true }
    }
  }
}

extension View {
  /// The sheets `EpisodeExtras` opens: chapters and transcript.
  func episodeSheets(item: Item, chapters: Binding<Bool>, transcript: Binding<Bool>) -> some View {
    modifier(EpisodeSheets(item: item, showChapters: chapters, showTranscript: transcript))
  }
}

private struct EpisodeSheets: ViewModifier {
  @Environment(Store.self) private var store
  let item: Item
  @Binding var showChapters: Bool
  @Binding var showTranscript: Bool
  @State private var chapters: [Chapter] = []

  func body(content: Content) -> some View {
    let playback = store.playback
    content
      .sheet(isPresented: $showChapters) {
        NavigationStack {
          ChapterList(item: item, chapters: playback.isCurrent(item) ? playback.chapters : chapters)
            .navigationTitle("Chapters")
            .inlineTitle()
            .toolbar {
              ToolbarItem(placement: .confirmationAction) {
                Button("Done") { showChapters = false }
              }
            }
        }
        .presentationDetents([.medium, .large])
        .macSheetSize(width: 420, height: 480)
        .task {
          if chapters.isEmpty { chapters = await store.chapters(for: item) }
        }
      }
      .sheet(isPresented: $showTranscript) {
        NavigationStack {
          TranscriptView(item: item)
            .toolbar {
              ToolbarItem(placement: .confirmationAction) {
                Button("Done") { showTranscript = false }
              }
            }
        }
        .macSheetSize(width: 480, height: 600)
      }
      .onChange(of: item.id) { chapters = [] }
  }
}

/// Plays an episode, or pauses it: what is downloaded (the video, if that
/// was saved), otherwise the audio.
struct PlayButton: View {
  @Environment(Store.self) private var store
  let item: Item

  var body: some View {
    let playback = store.playback
    let current = store.item(item.id) ?? item
    let playsVideo = Playback.downloadedVideo(item)
    // Playing (or paused) the way this button plays it.
    let mine = playback.isCurrent(item) && playback.isVideo == playsVideo
    let label =
      mine
      ? (playback.isPlaying ? "Pause" : "Resume")
      : current.resumeAt > 0 ? "Resume from \(formatTime(Double(current.resumeAt)))" : "Play"
    Button(label, systemImage: mine && playback.isPlaying ? "pause.fill" : "play.fill") {
      Task { await playback.play(current) }
    }
  }
}

/// Adds an episode to Up Next, or takes it out.
struct UpNextButton: View {
  @Environment(Store.self) private var store
  let item: Item

  var body: some View {
    let queued = store.isQueued(item)
    Button(
      queued ? "Remove from Up Next" : "Add to Up Next",
      systemImage: queued ? "text.badge.checkmark" : "text.badge.plus"
    ) {
      Task {
        if queued {
          await store.dequeue(item)
        } else {
          await store.enqueue(item)
        }
      }
    }
  }
}

/// Saves an episode to play offline: its audio, or its video; shows the
/// progress, and removes it.
struct DownloadButton: View {
  let item: Item

  var body: some View {
    let downloads = Downloads.shared
    let canVideo = Downloads.canDownload(item, video: true)
    let state = downloads.state(item.id)
    if Downloads.canDownload(item) {
      Menu {
        switch state {
        case .none:
          Button("Download", systemImage: "arrow.down.circle") { downloads.download(item) }
          if canVideo {
            Button("Download Video", systemImage: "play.rectangle") {
              downloads.download(item, video: true)
            }
          }
        case .downloading(let fraction):
          Text("Downloading, \(Int(fraction * 100))%")
          Button("Cancel Download", systemImage: "xmark.circle", role: .destructive) {
            downloads.remove(item.id)
          }
        case .saved(let download):
          Text(
            "\(download.kind == .video ? "Video" : "Audio") saved, "
              + ByteCountFormatter.string(fromByteCount: download.bytes, countStyle: .file))
          if download.kind == .audio && canVideo {
            Button("Download Video Instead", systemImage: "play.rectangle") {
              downloads.download(item, video: true)
            }
          }
          Button("Remove Download", systemImage: "trash", role: .destructive) {
            downloads.remove(item.id)
          }
        case .failed(let message):
          Text("Download failed: \(message)")
          Button("Try Again", systemImage: "arrow.clockwise") { downloads.download(item) }
        }
      } label: {
        Label(Self.title(state), systemImage: Self.symbol(state))
      }
      .labelStyle(.iconOnly)
    }
  }

  static func title(_ state: Downloads.State) -> String {
    switch state {
    case .none: "Download"
    case .downloading: "Downloading"
    case .saved: "Downloaded"
    case .failed: "Download failed"
    }
  }

  static func symbol(_ state: Downloads.State) -> String {
    switch state {
    case .none: "arrow.down.circle"
    case .downloading: "arrow.down.circle.dotted"
    case .saved: "arrow.down.circle.fill"
    case .failed: "exclamationmark.circle"
    }
  }
}
