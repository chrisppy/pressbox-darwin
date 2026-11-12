// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import AVKit
import SwiftUI

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

/// An episode's chapters; while it plays, the current one is marked and a
/// tap jumps to one.
struct ChapterList: View {
  @Environment(Store.self) private var store
  let item: Item
  let chapters: [Chapter]

  var body: some View {
    let playback = store.playback
    let playing = playback.isCurrent(item)
    let current = playing ? playback.chapter : nil
    List(chapters.filter { !$0.isHidden }) { chapter in
      Button {
        if playing { playback.seek(to: chapter.start) }
      } label: {
        HStack {
          Text(formatTime(chapter.start))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(minWidth: 56, alignment: .leading)
          Text(chapter.title ?? "")
            .fontWeight(current == chapter ? .semibold : .regular)
          Spacer()
          if current == chapter {
            Image(systemName: "speaker.wave.2.fill").foregroundStyle(Color.accentColor)
          }
        }
      }
      .disabled(!playing)
      .foregroundStyle(.primary)
    }
    .overlay {
      if chapters.isEmpty {
        ContentUnavailableView("No chapters yet", systemImage: "list.bullet")
      }
    }
  }
}

/// An episode's transcript; while it plays, the line being heard is
/// highlighted and followed, and a tap jumps to a line.
struct TranscriptView: View {
  @Environment(Store.self) private var store
  let item: Item
  @State private var transcript: Transcript?
  @State private var loaded = false

  var body: some View {
    let playback = store.playback
    let playing = playback.isCurrent(item)
    let now = playing ? playback.position : nil
    let current = now.flatMap { at in transcript?.segments.last { $0.start <= at && at < $0.end } }
    ScrollViewReader { proxy in
      List(transcript?.segments ?? []) { segment in
        Button {
          if playing { playback.seek(to: segment.start) }
        } label: {
          VStack(alignment: .leading, spacing: 2) {
            HStack {
              Text(formatTime(segment.start)).monospacedDigit()
              if let speaker = segment.speaker {
                Text(speaker).fontWeight(.semibold)
              }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(segment.text)
              .foregroundStyle(segment == current ? Color.accentColor : .primary)
          }
        }
        .disabled(!playing)
        .id(segment.id)
      }
      .listStyle(.plain)
      .onChange(of: current) { _, segment in
        if let segment { withAnimation { proxy.scrollTo(segment.id, anchor: .center) } }
      }
    }
    .overlay {
      if !loaded {
        ProgressView()
      } else if transcript == nil {
        ContentUnavailableView("No transcript", systemImage: "text.quote")
      }
    }
    .navigationTitle("Transcript")
    .inlineTitle()
    .task {
      transcript = await store.transcript(for: item)
      loaded = true
    }
  }
}

/// The bar above every screen's controls while an episode plays: tap it
/// for the full player.
struct MiniPlayer: View {
  @Environment(Store.self) private var store
  @State private var showPlayer = false

  var body: some View {
    let playback = store.playback
    if let item = playback.item {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(1)
          Text(playback.chapter?.title ?? store.feedTitle(item.feedId))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { showPlayer = true }
        Button("Back \(Int(Playback.skipBack)) seconds", systemImage: "gobackward.10") {
          playback.skip(-Playback.skipBack)
        }
        .labelStyle(.iconOnly)
        Button(
          playback.isPlaying ? "Pause" : "Play",
          systemImage: playback.isPlaying ? "pause.fill" : "play.fill"
        ) {
          playback.togglePause()
        }
        .labelStyle(.iconOnly)
        .font(.title3)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .overlay(alignment: .bottom) {
        if let d = playback.duration, d > 0 {
          ProgressView(value: min(playback.position, d), total: d)
            .progressViewStyle(.linear)
        }
      }
      .statusBanner()
      .sheet(isPresented: $showPlayer) {
        NowPlayingView()
          .macSheetSize(width: 440, height: 640)
      }
    }
  }
}

/// The full player.
struct NowPlayingView: View {
  @Environment(Store.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var showChapters = false
  @State private var showTranscript = false
  @State private var showUpNext = false

  var body: some View {
    let playback = store.playback
    NavigationStack {
      VStack(spacing: 20) {
        if let item = playback.item {
          if playback.isVideo {
            VideoView(player: playback.player)
              .aspectRatio(16 / 9, contentMode: .fit)
              .clipShape(RoundedRectangle(cornerRadius: 12))
          } else {
            Artwork(item: item)
          }
          VStack(spacing: 4) {
            Text(item.title).font(.headline).multilineTextAlignment(.center)
            Text(playback.chapter?.title ?? store.feedTitle(item.feedId))
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          ScrubBar()
          controls
          HStack(spacing: 24) {
            Button("\(Self.rateLabel(playback.rate))×") { playback.nextRate() }
              .monospacedDigit()
            if !playback.chapters.isEmpty {
              Button("Chapters", systemImage: "list.bullet") { showChapters = true }
                .labelStyle(.iconOnly)
            }
            if item.media?.hasTranscript ?? false {
              Button("Transcript", systemImage: "text.quote") { showTranscript = true }
                .labelStyle(.iconOnly)
            }
            if store.hasQueue {
              Button("Up Next", systemImage: Self.upNextSymbol) { showUpNext = true }
                .labelStyle(.iconOnly)
            }
            RoutePicker().frame(width: 32, height: 32)
            Button("Stop", systemImage: "stop.fill") {
              Task {
                await playback.stop()
                dismiss()
              }
            }
            .labelStyle(.iconOnly)
          }
          .font(.title3)
        } else {
          ContentUnavailableView("Nothing playing", systemImage: "waveform")
        }
        if let message = playback.errorMessage {
          Text(message).font(.footnote).foregroundStyle(Theme.error)
        }
      }
      .padding(24)
      .frame(maxHeight: .infinity, alignment: .top)
      .themedScreen()
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
      .sheet(isPresented: $showChapters) {
        if let item = playback.item {
          NavigationStack {
            ChapterList(item: item, chapters: playback.chapters)
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
        }
      }
      .sheet(isPresented: $showTranscript) {
        if let item = playback.item {
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
      }
      .sheet(isPresented: $showUpNext) {
        UpNextView()
      }
    }
  }

  static let upNextSymbol = "text.line.first.and.arrowtriangle.forward"

  private static func rateLabel(_ rate: Float) -> String {
    rate == rate.rounded() ? String(Int(rate)) : String(format: "%g", rate)
  }

  private var controls: some View {
    let playback = store.playback
    return HStack(spacing: 32) {
      Button("Previous chapter", systemImage: "backward.end.fill") {
        playback.jumpChapter(next: false)
      }
      .disabled(playback.chapters.isEmpty)
      Button("Back \(Int(Playback.skipBack)) seconds", systemImage: "gobackward.10") {
        playback.skip(-Playback.skipBack)
      }
      Button(
        playback.isPlaying ? "Pause" : "Play",
        systemImage: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill"
      ) {
        playback.togglePause()
      }
      .font(.system(size: 56))
      Button("Forward \(Int(Playback.skipForward)) seconds", systemImage: "goforward.30") {
        playback.skip(Playback.skipForward)
      }
      Button("Next chapter", systemImage: "forward.end.fill") {
        playback.jumpChapter(next: true)
      }
      .disabled(playback.chapters.isEmpty)
    }
    .labelStyle(.iconOnly)
    .font(.title2)
  }
}

/// The episode's artwork, or the feed's.
/// The progress slider and times. Dragging is its own state, kept out of
/// the player around it: redrawing the player while dragging also redrew
/// the video, which could leave it black while the audio played on.
private struct ScrubBar: View {
  @Environment(Store.self) private var store
  @State private var scrubbing: Double?

  var body: some View {
    let playback = store.playback
    let duration = max(playback.duration ?? playback.position, 1)
    let shown = scrubbing ?? playback.position
    VStack(spacing: 4) {
      Slider(
        value: Binding(get: { shown }, set: { scrubbing = $0 }),
        in: 0...duration,
        onEditingChanged: { editing in
          if !editing, let to = scrubbing {
            playback.seek(to: to)
            scrubbing = nil
          }
        })
      HStack {
        Text(formatTime(shown))
        Spacer()
        if playback.isLoading {
          ProgressView().controlSize(.small)
        }
        Spacer()
        Text(playback.duration.map { "-" + formatTime($0 - shown) } ?? "")
      }
      .font(.caption.monospacedDigit())
      .foregroundStyle(.secondary)
    }
  }
}

private struct Artwork: View {
  @Environment(Store.self) private var store
  let item: Item

  private var url: URL? {
    let image =
      store.playback.chapter?.image ?? item.media?.image
      ?? store.feeds.first { $0.id == item.feedId }?.image
    return image.flatMap(URL.init(string:))
  }

  var body: some View {
    AsyncImage(url: url) { image in
      image.resizable().scaledToFit()
    } placeholder: {
      Image(systemName: "waveform")
        .font(.system(size: 64))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.quaternary)
    }
    .frame(maxWidth: 320, maxHeight: 320)
    .aspectRatio(1, contentMode: .fit)
    .clipShape(RoundedRectangle(cornerRadius: 16))
  }
}

/// The episodes to play next, in order: tap one to play it, drag to
/// reorder, swipe (or Delete on Mac) to remove. When an episode ends, the
/// first one here starts.
struct UpNextView: View {
  @Environment(Store.self) private var store
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        ForEach(store.queue) { item in
          Button {
            Task { await store.playback.play(item) }
          } label: {
            ItemRow(item: item, feedTitle: store.feedTitle(item.feedId))
          }
          .foregroundStyle(.primary)
          .contextMenu {
            Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
              Task { await store.enqueue(item, next: true) }
            }
            Button("Remove from Up Next", systemImage: "minus.circle", role: .destructive) {
              Task { await store.dequeue(item) }
            }
          }
        }
        .onMove { from, to in
          var queue = store.queue
          queue.move(fromOffsets: from, toOffset: to)
          Task { await store.setQueue(queue) }
        }
        .onDelete { offsets in
          var queue = store.queue
          queue.remove(atOffsets: offsets)
          Task { await store.setQueue(queue) }
        }
      }
      .listStyle(.plain)
      .themedScreen()
      .overlay {
        if store.queue.isEmpty {
          ContentUnavailableView(
            "Up Next is empty", systemImage: NowPlayingView.upNextSymbol,
            description: Text(
              "Swipe an episode in a list, or use Add to Up Next in its bottom bar, to queue it."))
        }
      }
      .navigationTitle("Up Next")
      .inlineTitle()
      .toolbar {
        #if os(iOS)
          ToolbarItem(placement: .cancellationAction) {
            EditButton().disabled(store.queue.isEmpty)
          }
        #endif
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
    .presentationDetents([.medium, .large])
    .macSheetSize(width: 420, height: 480)
  }
}

extension View {
  /// A small title in the bar, on iPhone and iPad; Mac sheets have none.
  @ViewBuilder fileprivate func inlineTitle() -> some View {
    #if os(iOS)
      navigationBarTitleDisplayMode(.inline)
    #else
      self
    #endif
  }

  /// Sheets on Mac have no size of their own.
  @ViewBuilder func macSheetSize(width: CGFloat, height: CGFloat) -> some View {
    #if os(macOS)
      frame(minWidth: width, idealWidth: width, minHeight: height, idealHeight: height)
    #else
      self
    #endif
  }
}

#if os(macOS)
  /// Video with the system's controls, full screen and picture in picture.
  struct VideoView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
      let view = AVPlayerView()
      view.player = player
      view.controlsStyle = .inline
      view.allowsPictureInPicturePlayback = true
      view.updatesNowPlayingInfoCenter = false
      return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
      // Setting it again, even to the same player, reattaches the video
      // layer; doing that on every redraw could leave the video black.
      if view.player !== player { view.player = player }
    }
  }

  /// AirPlay and other outputs.
  private struct RoutePicker: NSViewRepresentable {
    func makeNSView(context: Context) -> AVRoutePickerView {
      let view = AVRoutePickerView()
      view.isRoutePickerButtonBordered = false
      return view
    }

    func updateNSView(_ view: AVRoutePickerView, context: Context) {}
  }
#else
  /// Video with the system's controls, full screen and picture in picture.
  struct VideoView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
      let controller = AVPlayerViewController()
      controller.player = player
      controller.allowsPictureInPicturePlayback = true
      controller.canStartPictureInPictureAutomaticallyFromInline = true
      controller.updatesNowPlayingInfoCenter = false
      return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
      // Setting it again, even to the same player, reattaches the video
      // layer; doing that on every redraw could leave the video black.
      if controller.player !== player { controller.player = player }
    }
  }

  /// AirPlay and other outputs.
  private struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
      let view = AVRoutePickerView()
      view.prioritizesVideoDevices = false
      return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
  }
#endif
