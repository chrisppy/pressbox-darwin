// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import AppIntents

/// The Up Next widget's play/pause button. An audio playback intent runs in
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

/// How the intent reaches the player: the app's store sets `toggle` when it
/// starts. The widget extension never sets it.
@MainActor
enum PlaybackBridge {
  static var toggle: (@MainActor () async -> Void)?
}
