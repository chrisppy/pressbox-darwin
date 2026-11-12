// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import AVFoundation
import MediaPlayer
import Observation

#if os(macOS)
  import AppKit
  private typealias PlatformImage = NSImage
#else
  import UIKit
  private typealias PlatformImage = UIImage
#endif

/// Plays podcast episodes with AVPlayer: in the background, on the Lock
/// Screen and Control Center (Now Playing; on Mac, Control Center and the
/// media keys), over AirPlay, and video in picture in picture. The position is saved on the server as it plays, so
/// any client resumes where this one stopped.
@MainActor
@Observable
final class Playback {
  /// The episode playing (or paused); `nil` when stopped.
  private(set) var item: Item? {
    didSet { if oldValue?.id != item?.id { store?.updateWidgets() } }
  }
  private(set) var isVideo = false
  private(set) var chapters: [Chapter] = []
  /// Seconds into the episode.
  private(set) var position: Double = 0
  private(set) var duration: Double?
  private(set) var isPlaying = false {
    didSet { if oldValue != isPlaying { store?.updateWidgets() } }
  }
  private(set) var isLoading = false
  private(set) var rate: Float = 1 {
    didSet { if oldValue != rate { store?.updateWidgets() } }
  }
  var errorMessage: String?

  /// The speeds the speed button steps through.
  static let rates: [Float] = [1, 1.25, 1.5, 1.75, 2, 0.75]
  /// The position is saved after it moves this many seconds while playing.
  static let saveEvery = 15
  /// Stopping this close to the end (seconds) counts as finishing.
  static let nearEnd: Double = 30
  static let skipForward: Double = 30
  static let skipBack: Double = 10

  /// For saving positions and marking episodes read.
  @ObservationIgnored weak var store: Store?
  /// The player, for the video view.
  let player = AVPlayer()

  @ObservationIgnored private var timeObserver: Any?
  @ObservationIgnored private var endObserver: NSObjectProtocol?
  @ObservationIgnored private var statusObserver: NSKeyValueObservation?
  @ObservationIgnored private var interruptionObserver: NSObjectProtocol?
  @ObservationIgnored private var saved = 0
  @ObservationIgnored private var artwork: MPMediaItemArtwork?

  init() {
    setUpRemoteCommands()
    #if os(iOS)
      observeInterruptions()
    #endif
  }

  #if os(iOS)
    /// A call or another app's audio pauses the episode; it resumes after if
    /// iOS says so.
    private func observeInterruptions() {
      interruptionObserver = NotificationCenter.default.addObserver(
        forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
      ) { [weak self] note in
        let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
          .map(AVAudioSession.InterruptionOptions.init(rawValue:))
        let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
          .flatMap(AVAudioSession.InterruptionType.init(rawValue:))
        MainActor.assumeIsolated {
          guard let self, self.item != nil else { return }
          switch type {
          case .began: self.isPlaying = false
          case .ended where options?.contains(.shouldResume) ?? false: self.resume()
          default: break
          }
        }
      }
    }
  #endif

  /// The chapter at the current position.
  var chapter: Chapter? {
    chapters.filter { !$0.isHidden }.last { $0.start <= position }
  }

  func isCurrent(_ item: Item) -> Bool { self.item?.id == item.id }

  // MARK: Playing

  /// Starts an episode (its video, with `video`), resuming where it was
  /// left; or, if it is the one playing that way, pauses or resumes it.
  func play(_ episode: Item, video: Bool = false) async {
    if item?.id == episode.id && isVideo == video {
      togglePause()
      return
    }
    guard let media = episode.media,
      let enclosure = video ? media.video : media.audio,
      // A downloaded file, when there is one.
      let url = Downloads.shared.file(for: episode.id, video: video) ?? URL(string: enclosure.url)
    else { return }
    let switching = item?.id == episode.id
    await stop()
    // Switching between an episode's audio and video carries on from where
    // the other stopped.
    var start = Double(store?.item(episode.id)?.resumeAt ?? episode.resumeAt)
    if switching { start = position }
    // Played to the end before: from the top.
    if let d = media.duration, start >= Double(d) - Self.nearEnd { start = 0 }

    #if os(iOS)
      do {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
          .playback, mode: video ? .moviePlayback : .spokenAudio,
          policy: video ? .default : .longFormAudio)
        try session.setActive(true)
      } catch {
        errorMessage = error.localizedDescription
      }
    #endif

    item = episode
    isVideo = video
    chapters = []
    position = start
    duration = media.duration.map(Double.init)
    saved = Int(start)
    isLoading = true
    errorMessage = nil

    let playerItem = AVPlayerItem(url: url)
    // Keep the pitch when playing faster.
    playerItem.audioTimePitchAlgorithm = .timeDomain
    statusObserver = playerItem.observe(\.status) { [weak self] playerItem, _ in
      let failed = playerItem.status == .failed
      let message = playerItem.error?.localizedDescription
      Task { @MainActor in
        guard let self else { return }
        self.isLoading = false
        if failed {
          self.errorMessage = message ?? "The episode couldn't be played."
          await self.stop()
        }
      }
    }
    endObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main
    ) { [weak self] _ in
      // As in the status observer: an explicitly main-actor task. A bare
      // `Task { await self?.finish() }` is ambiguous between Task's
      // initializers with the iOS 26 SDK.
      Task { @MainActor in
        guard let self else { return }
        await self.finish(advance: true)
      }
    }
    player.replaceCurrentItem(with: playerItem)
    if start > 0 {
      _ = await player.seek(to: CMTime(seconds: start, preferredTimescale: 1))
    }
    player.defaultRate = rate
    player.play()
    isPlaying = true
    timeObserver = player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 1, preferredTimescale: 1), queue: .main
    ) { [weak self] time in
      MainActor.assumeIsolated { self?.tick(time) }
    }
    loadArtwork(for: episode)
    updateNowPlaying()

    if media.chapters != nil, let store {
      let loaded = await store.chapters(for: episode)
      // Unless another episode has started meanwhile.
      if item?.id == episode.id {
        chapters = loaded
        updateNowPlaying()
      }
    }
  }

  func togglePause() {
    if isPlaying { pause() } else { resume() }
  }

  func pause() {
    guard item != nil else { return }
    player.pause()
    isPlaying = false
    updateNowPlaying()
    Task { await save() }
  }

  func resume() {
    guard item != nil else { return }
    player.play()
    player.rate = rate
    isPlaying = true
    updateNowPlaying()
  }

  func seek(to seconds: Double) {
    guard item != nil else { return }
    let to = max(0, duration.map { min(seconds, $0) } ?? seconds)
    position = to
    player.seek(to: CMTime(seconds: to, preferredTimescale: 600))
    updateNowPlaying()
  }

  func skip(_ by: Double) { seek(to: position + by) }

  /// The next chapter, or (`next` false) the start of this one, or the one
  /// before near its start.
  func jumpChapter(next: Bool) {
    let starts = chapters.filter { !$0.isHidden }.map(\.start)
    if next {
      if let to = starts.first(where: { $0 > position + 0.5 }) { seek(to: to) }
    } else {
      seek(to: starts.last { $0 < position - 3 } ?? 0)
    }
  }

  /// Steps through `rates`.
  func nextRate() {
    let i = Self.rates.firstIndex(of: rate).map { ($0 + 1) % Self.rates.count } ?? 0
    setRate(Self.rates[i])
  }

  func setRate(_ value: Float) {
    rate = value
    player.defaultRate = value
    if isPlaying { player.rate = value }
    updateNowPlaying()
  }

  /// Stops playing, saving the position (or, near the end, finishing).
  func stop() async {
    guard item != nil else { return }
    if let d = duration, position >= d - Self.nearEnd {
      await finish()
      return
    }
    await save()
    teardown()
  }

  /// Stops without saving (signing out).
  func discard() { teardown() }

  /// Played to the end: marks the episode read and forgets its position.
  /// With `advance`, carries on with the next episode in Up Next.
  private func finish(advance: Bool = false) async {
    guard let item else { return }
    let next = advance ? store?.queue.first(where: { $0.id != item.id }) : nil
    // Going on to the next episode, keep the audio session: iOS may not let
    // a backgrounded app activate it again.
    teardown(deactivate: next == nil)
    guard let next else {
      await store?.finished(item)
      return
    }
    // Start the next one first: marking this one done waits on the network.
    Task { await store?.finished(item) }
    await play(next)
  }

  private func teardown(deactivate: Bool = true) {
    player.pause()
    if let timeObserver { player.removeTimeObserver(timeObserver) }
    if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    timeObserver = nil
    endObserver = nil
    statusObserver = nil
    player.replaceCurrentItem(with: nil)
    item = nil
    isPlaying = false
    isLoading = false
    chapters = []
    artwork = nil
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    MPNowPlayingInfoCenter.default().playbackState = .stopped
    #if os(iOS)
      if deactivate {
        try? AVAudioSession.sharedInstance().setActive(
          false, options: .notifyOthersOnDeactivation)
      }
    #endif
  }

  private func tick(_ time: CMTime) {
    guard item != nil, time.isNumeric else { return }
    position = time.seconds
    if let d = player.currentItem?.duration, d.isNumeric, d.seconds > 0 {
      duration = d.seconds
    }
    isPlaying = player.timeControlStatus != .paused
    if abs(Int(position) - saved) >= Self.saveEvery {
      Task { await save() }
    }
    updateNowPlaying()
  }

  private func save() async {
    guard let item else { return }
    let at = Int(max(0, position))
    guard at != saved else { return }
    saved = at
    await store?.savePosition(item, at)
  }

  // MARK: Now Playing and remote commands

  private func updateNowPlaying() {
    guard let item else { return }
    var info: [String: Any] = [
      MPMediaItemPropertyTitle: chapter?.title.map { "\(item.title) · \($0)" } ?? item.title,
      MPMediaItemPropertyArtist: store?.feedTitle(item.feedId) ?? item.feedId,
      MPMediaItemPropertyAlbumTitle: store?.feedTitle(item.feedId) ?? item.feedId,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
      MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0,
      MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(rate),
      MPNowPlayingInfoPropertyMediaType: isVideo
        ? MPNowPlayingInfoMediaType.video.rawValue : MPNowPlayingInfoMediaType.audio.rawValue,
    ]
    if let duration { info[MPMediaItemPropertyPlaybackDuration] = duration }
    if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
  }

  /// The episode's (or else the feed's) artwork, for the Lock Screen.
  private func loadArtwork(for item: Item) {
    let image = item.media?.image ?? store?.feeds.first { $0.id == item.feedId }?.image
    guard let image, let url = URL(string: image) else { return }
    Task {
      guard let response = try? await URLSession.shared.data(from: url),
        let picture = PlatformImage(data: response.0), self.item?.id == item.id
      else { return }
      artwork = MPMediaItemArtwork(boundsSize: picture.size) { _ in picture }
      updateNowPlaying()
    }
  }

  private func setUpRemoteCommands() {
    let center = MPRemoteCommandCenter.shared()
    center.playCommand.addTarget { [weak self] _ in
      MainActor.assumeIsolated { self?.resume() }
      return .success
    }
    center.pauseCommand.addTarget { [weak self] _ in
      MainActor.assumeIsolated { self?.pause() }
      return .success
    }
    center.togglePlayPauseCommand.addTarget { [weak self] _ in
      MainActor.assumeIsolated { self?.togglePause() }
      return .success
    }
    center.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.skipForward)]
    center.skipForwardCommand.addTarget { [weak self] _ in
      MainActor.assumeIsolated { self?.skip(Self.skipForward) }
      return .success
    }
    center.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.skipBack)]
    center.skipBackwardCommand.addTarget { [weak self] _ in
      MainActor.assumeIsolated { self?.skip(-Self.skipBack) }
      return .success
    }
    center.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let event = event as? MPChangePlaybackPositionCommandEvent else {
        return .commandFailed
      }
      MainActor.assumeIsolated { self?.seek(to: event.positionTime) }
      return .success
    }
    center.changePlaybackRateCommand.supportedPlaybackRates = Self.rates.map {
      NSNumber(value: $0)
    }
    center.changePlaybackRateCommand.addTarget { [weak self] event in
      guard let event = event as? MPChangePlaybackRateCommandEvent else {
        return .commandFailed
      }
      MainActor.assumeIsolated { self?.setRate(event.playbackRate) }
      return .success
    }
    center.nextTrackCommand.isEnabled = false
    center.previousTrackCommand.isEnabled = false
  }
}

/// `m:ss`, or `h:mm:ss` from an hour.
func formatTime(_ seconds: Double) -> String {
  let s = Int(max(0, seconds.isFinite ? seconds : 0))
  let (h, m, sec) = (s / 3600, s / 60 % 60, s % 60)
  return h > 0
    ? String(format: "%d:%02d:%02d", h, m, sec)
    : String(format: "%d:%02d", m, sec)
}
