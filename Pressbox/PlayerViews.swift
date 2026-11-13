// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import AVKit
import SwiftUI

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
        // Apart, each with a full-size target, so a tap meant for one
        // doesn't land on the other.
        HStack(spacing: 20) {
          Button("Back \(Int(Playback.skipBack)) seconds", systemImage: "gobackward.10") {
            playback.skip(-Playback.skipBack)
          }
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
          Button(
            playback.isPlaying ? "Pause" : "Play",
            systemImage: playback.isPlaying ? "pause.fill" : "play.fill"
          ) {
            playback.togglePause()
          }
          .font(.title3)
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
        }
        .labelStyle(.iconOnly)
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
            sleepMenu
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
          if let sleepAt = playback.sleepAt {
            HStack(spacing: 4) {
              Text("Pauses in")
              Text(timerInterval: Date.now...max(sleepAt, .now), countsDown: true)
                .monospacedDigit()
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
          } else if playback.sleepTimer == .endOfEpisode {
            Text("Pauses at the end of this episode")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
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

  /// The sleep timer: off, a number of minutes, or the end of the episode.
  private var sleepMenu: some View {
    let playback = store.playback
    return Menu {
      Button("Off") { playback.setSleepTimer(nil) }
        .disabled(playback.sleepTimer == nil)
      ForEach(Playback.sleepMinutes, id: \.self) { minutes in
        Button("\(minutes) minutes") { playback.setSleepTimer(.minutes(minutes)) }
      }
      Button("End of Episode") { playback.setSleepTimer(.endOfEpisode) }
    } label: {
      Label(
        "Sleep Timer", systemImage: playback.sleepTimer == nil ? "moon.zzz" : "moon.zzz.fill")
    }
    .labelStyle(.iconOnly)
  }

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

/// The episode's artwork, or the feed's.
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

extension View {
  /// A small title in the bar, on iPhone and iPad; Mac sheets have none.
  @ViewBuilder func inlineTitle() -> some View {
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
