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

  /// Pauses playback after a while, or at the end of the episode.
  enum SleepTimer: Equatable {
    case minutes(Int)
    case endOfEpisode
  }

  /// The sleep timer set, if any.
  private(set) var sleepTimer: SleepTimer?
  /// When a timed sleep timer pauses.
  private(set) var sleepAt: Date?
  @ObservationIgnored private var sleepTask: Task<Void, Never>?

  /// The sleep timer's choices, in minutes.
  static let sleepMinutes = [15, 30, 45, 60]

  /// The speeds the speed button steps through.
  static let rates: [Float] = [1, 1.25, 1.5, 1.75, 2, 0.75]
  /// The position is saved after it moves this many seconds while playing.
  static let saveEvery = 15
  /// Stopping this close to the end (seconds) counts as finishing.
  static let nearEnd: Double = 30
  /// The skip lengths Settings offers, in seconds: each has SF Symbols,
  /// `gobackward.N` and `goforward.N`.
  static let skipChoices = [5, 10, 15, 30, 45, 60]

  /// Seconds the skip buttons jump, here and on the Lock Screen: set in
  /// Settings.
  var skipForward: Double = 30 {
    didSet {
      UserDefaults.standard.set(Int(skipForward), forKey: "skipForward")
      updateSkipCommands()
    }
  }
  var skipBack: Double = 10 {
    didSet {
      UserDefaults.standard.set(Int(skipBack), forKey: "skipBack")
      updateSkipCommands()
    }
  }
  var skipForwardSymbol: String { "goforward.\(Int(skipForward))" }
  var skipBackSymbol: String { "gobackward.\(Int(skipBack))" }

  /// The speed for podcasts without one of their own: set in Settings.
  var defaultRate: Float = 1 {
    didSet {
      UserDefaults.standard.set(defaultRate, forKey: "defaultRate")
      if let item, feedRates[item.feedId] == nil { setRate(defaultRate, remember: false) }
    }
  }
  /// Each podcast's own speed, by feed id: the last one set while one of
  /// its episodes played.
  @ObservationIgnored private var feedRates: [String: Float] = [:]

  /// "1.5×".
  static func rateLabel(_ rate: Float) -> String {
    (rate == rate.rounded() ? String(Int(rate)) : String(format: "%g", rate)) + "×"
  }

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
    let defaults = UserDefaults.standard
    skipForward = Self.skipChoice(defaults.integer(forKey: "skipForward"), else: 30)
    skipBack = Self.skipChoice(defaults.integer(forKey: "skipBack"), else: 10)
    if let rate = defaults.object(forKey: "defaultRate") as? Float, Self.rates.contains(rate) {
      defaultRate = rate
    }
    feedRates = (defaults.dictionary(forKey: "feedRates") as? [String: Float]) ?? [:]
    rate = defaultRate
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

  private static func skipChoice(_ seconds: Int, else fallback: Double) -> Double {
    skipChoices.contains(seconds) ? Double(seconds) : fallback
  }

  /// The chapter at the current position.
  var chapter: Chapter? {
    chapters.filter { !$0.isHidden }.last { $0.start <= position }
  }

  func isCurrent(_ item: Item) -> Bool { self.item?.id == item.id }

  // MARK: Playing

  /// Starts an episode (its video, with `video`), resuming where it was
  /// left; or, if it is the one playing that way, pauses or resumes it.
  /// Without `video`, it plays what is downloaded: the video if that was
  /// saved, otherwise the audio.
  func play(_ episode: Item, video: Bool? = nil) async {
    let video = video ?? Self.downloadedVideo(episode)
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
      // initializers since the iOS 26 SDK.
      Task { @MainActor in
        guard let self else { return }
        await self.finish(advance: true)
      }
    }
    // The podcast's own speed; switching between audio and video keeps
    // the one playing.
    if !switching { rate = feedRates[episode.feedId] ?? defaultRate }
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

  /// The episode's download is its video.
  static func downloadedVideo(_ episode: Item) -> Bool {
    Downloads.shared.saved[episode.id]?.kind == .video
  }

  /// Sets the sleep timer, or (`nil`) turns it off. The app plays in the
  /// background, so the timer runs with it closed.
  func setSleepTimer(_ timer: SleepTimer?) {
    sleepTask?.cancel()
    sleepTask = nil
    sleepTimer = timer
    sleepAt = nil
    guard case .minutes(let minutes) = timer else { return }
    sleepAt = Date().addingTimeInterval(TimeInterval(minutes * 60))
    sleepTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(minutes * 60))
      guard !Task.isCancelled, let self else { return }
      self.pause()
      self.setSleepTimer(nil)
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

  /// Sets the speed, and (with `remember`) keeps it for the podcast
  /// playing: its episodes play at this speed from now on.
  func setRate(_ value: Float, remember: Bool = true) {
    rate = value
    player.defaultRate = value
    if isPlaying { player.rate = value }
    updateNowPlaying()
    guard remember, let item else { return }
    feedRates[item.feedId] = value == defaultRate ? nil : value
    UserDefaults.standard.set(feedRates, forKey: "feedRates")
  }

  /// Stops playing, saving the position (or, near the end, finishing).
  func stop() async {
    guard item != nil else { return }
    setSleepTimer(nil)
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
    // A sleep timer for the end of the episode: stop here, not on into Up
    // Next.
    let sleeping = sleepTimer == .endOfEpisode
    if sleeping { setSleepTimer(nil) }
    let next = advance && !sleeping ? store?.queue.first(where: { $0.id != item.id }) : nil
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
    guard let url = URL(artwork: image) else { return }
    Task {
      guard let response = try? await URLSession.shared.data(from: url),
        let picture = PlatformImage(data: response.0), self.item?.id == item.id
      else { return }
      artwork = MPMediaItemArtwork(boundsSize: picture.size) { _ in picture }
      updateNowPlaying()
    }
  }

  /// The Lock Screen's and Control Center's skip buttons, as set.
  private func updateSkipCommands() {
    let center = MPRemoteCommandCenter.shared()
    center.skipForwardCommand.preferredIntervals = [NSNumber(value: skipForward)]
    center.skipBackwardCommand.preferredIntervals = [NSNumber(value: skipBack)]
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
    updateSkipCommands()
    center.skipForwardCommand.addTarget { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.skip(self.skipForward)
      }
      return .success
    }
    center.skipBackwardCommand.addTarget { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.skip(-self.skipBack)
      }
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
