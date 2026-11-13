// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import AppIntents

/// What Siri and Spotlight offer without any setup, and what the Shortcuts
/// app (and through it the Action button) lists for pressbox.
struct PressboxShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: TogglePlaybackIntent(),
      phrases: [
        "Play or pause \(.applicationName)",
        "Pause \(.applicationName)",
        "Resume \(.applicationName)",
        "Play Up Next in \(.applicationName)",
      ],
      shortTitle: "Play or Pause",
      systemImageName: "playpause.fill")
    AppShortcut(
      intent: SkipForwardIntent(),
      phrases: ["Skip forward in \(.applicationName)"],
      shortTitle: "Skip Forward",
      systemImageName: "goforward.30")
    AppShortcut(
      intent: SkipBackIntent(),
      phrases: ["Skip back in \(.applicationName)"],
      shortTitle: "Skip Back",
      systemImageName: "gobackward.10")
  }
}
