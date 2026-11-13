// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import AppIntents

/// Play or pause: the Up Next widget's button, the Control Center control,
/// Siri, Shortcuts and the Action button. An audio playback intent runs in
/// the app's process (launching it in the background if need be), where the
/// player is, rather than in the widget extension's.
struct TogglePlaybackIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Play or Pause"
  static let description = IntentDescription(
    "Pauses or resumes the episode playing, or plays the first one in Up Next.")

  init() {}

  @MainActor
  func perform() async throws -> some IntentResult {
    await PlaybackBridge.toggle?()
    return .result()
  }
}

/// Skips forward 30 seconds in the episode playing: Siri, Shortcuts and the
/// Action button.
struct SkipForwardIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Skip Forward"
  static let description = IntentDescription("Skips forward 30 seconds in the episode playing.")

  init() {}

  @MainActor
  func perform() async throws -> some IntentResult {
    PlaybackBridge.skip?(30)
    return .result()
  }
}

/// Skips back 10 seconds in the episode playing.
struct SkipBackIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Skip Back"
  static let description = IntentDescription("Skips back 10 seconds in the episode playing.")

  init() {}

  @MainActor
  func perform() async throws -> some IntentResult {
    PlaybackBridge.skip?(-10)
    return .result()
  }
}

/// How the intents reach the player: the app's store sets these when it
/// starts. The widget extension never does; its buttons and controls run the
/// intents in the app's process.
@MainActor
enum PlaybackBridge {
  static var toggle: (@MainActor () async -> Void)?
  /// Seconds forward (or, negative, back).
  static var skip: (@MainActor (Double) -> Void)?
}
