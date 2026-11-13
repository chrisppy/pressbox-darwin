<!--
SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
SPDX-License-Identifier: MPL-2.0
-->

# pressbox-darwin

The iPhone, iPad and Mac app for
[pressbox](https://github.com/red-oxide/pressbox), a self-hosted feed reader
whose feeds and users are declared in NixOS. It reads from your pressbox server
over its HTTP API (`/api/v1`) and shares read and starred state with the other
clients, such as the `pressbox` terminal reader.

> [!NOTE]
> pressbox-darwin is in its early days. Expect rough edges, and features and
> behavior that may change between versions.

## Requirements

- iOS 18 or later on iPhone and iPad, or macOS 15 or later on a Mac.
- A pressbox server reachable over HTTPS. iOS only allows plain HTTP to local
  network addresses (the same goes for macOS); `tailscale serve --bg 8470` on
  the server is the least work, and a reverse proxy with ACME works too.
- To build: a Mac with Xcode 26 or later and
  [XcodeGen](https://github.com/yonaskolb/XcodeGen).

## Building

The repo holds an XcodeGen spec (`project.yml`) and the SwiftUI sources
(`Pressbox/`); the Xcode project is generated, not committed. One target builds
for iPhone, iPad and Mac; platform differences are `#if os(macOS)` blocks.

```sh
nix develop    # provides xcodegen on macOS, or: brew install xcodegen
just open      # xcodegen, then open Pressbox.xcodeproj
```

Set your team under Signing & Capabilities (or `DEVELOPMENT_TEAM` in
`project.yml`), pick an iOS device, a simulator or My Mac, and run it. CI builds
the app for the iOS simulator and for macOS on every change, and runs the unit
tests (`PressboxTests/`, with Swift Testing) in an iPhone simulator
(`.github/workflows/apple.yml`); `just build` and `just test-app` do the same
locally (`just build-ios` or `just build-mac` for one platform).

The logic with no screens (the API client and its JSON, the offline outbox,
which file a download saves, time formatting) is in `Core/`, which the app
compiles and `Package.swift` also builds as a Swift package. `just test` runs
its tests with `swift test`, on Linux too, in seconds and without Xcode
(`just coverage` adds a coverage report); CI runs them on Linux as well. Keep
`Core/` to Foundation, so it still builds there: anything that needs UIKit,
AVFoundation, WidgetKit and the like stays in `Pressbox/`.

## Using it

On first launch, enter the server address and tap "Pair this device". The app
shows a code like `K7W-4QX`: approve it on the server with
`sudo pressboxctl approve K7W-4QX`, or from a device that is already paired
(`pressbox approve K7W-4QX`). See pressbox's docs on
[pairing](https://github.com/red-oxide/pressbox/blob/master/docs/pairing.md) and
[users](https://github.com/red-oxide/pressbox/blob/master/docs/server.md#users).

Settings also has:

- **Approve a device**, for pairing other clients from your phone. Admins can
  approve a device for another user.
- **Require Face ID** (Touch ID on Mac), which locks the app whenever it goes to
  the background (on Mac: when it's hidden or its window is minimized).
- **Mark as read when scrolled past**, off by default: items are marked read as
  they scroll off the top of the list while you scroll (not in search results).
- **Unread count on app icon**, kept current by background refresh (on Mac, in
  the Dock, reloaded every 15 minutes while the app is open).

On Mac, Settings is in the app menu (⌘,), Reload is ⌘R and Refresh Feeds on
Server is ⇧⌘R, and each column's buttons are in the window toolbar.

The Server section shows the address, the signed-in user and device, and the
server's version.

### Downloads

Episodes can be saved to play without a connection. The audio of the 10 newest
unread episodes downloads by itself as they come in (turn it off in Settings),
and any episode's audio or video downloads from the Download button in its
bottom bar, which also shows the progress and removes it. Lists mark saved
episodes with a filled arrow. Downloads carry on with the app closed.

Settings › Downloads chooses **Wi-Fi only** (the default) or **Wi-Fi and
cellular** on iPhone and iPad, shows the space used, and removes everything. A
download is removed once its episode is finished or read (here or in any other
client), and an automatic one once it is no longer among the 10 newest unread.
Streams (HLS) can't be saved, so an episode that only has one plays online.

### Siri, Shortcuts and Control Center

"Play or pause pressbox", "Pause pressbox", "Play Up Next in pressbox", "Skip
forward in pressbox" and "Skip back in pressbox" work with Siri, without setup.
The same actions are in the Shortcuts app, so the Action button can run them,
and Control Center (iPhone and iPad) has a pressbox play/pause control. All of
them work with the app closed.

### Widgets

Two widgets, for the Home Screen and Today view on iPhone and iPad and the
desktop and Notification Center on Mac:

- **Unread**: the unread count (small), or the count and the newest unread items
  (medium and large); tap an item to open it. On the iPhone and iPad Lock Screen
  it shows the count, or the count and the newest title.
- **Up Next**: the episode playing, or the first in Up Next, with a progress bar
  and a play/pause button that works without opening the app; the medium size
  also lists what plays next.

The widgets show what the app last saw, through an App Group
(`group.org.red-oxide.pressbox`): they redraw when the app changes something
and, on iPhone and iPad, after background refreshes.

### Podcasts

Podcast episodes (items with audio or video) show a waveform in the list, a
half-filled circle once started, and a speaker while playing. An episode's
bottom bar has Play (resuming where it was left), Up Next, Download, and More:
Watch Video, Chapters and Transcript when it has them, then star, read, share
and Safari. Its byline adds the length, season and episode, and where it was
left. Opening an episode doesn't mark it read; playing it to the end (or
stopping in its last 30 seconds) does.

While an episode plays, a bar sits above the controls of every screen but an
episode's own (whose bottom bar has Play, and Now Playing in More); tap it for
the full player: artwork (the chapter's, when it has one), a scrubber, back 10 /
forward 30 seconds, previous and next chapter, the speed (1× to 2×, and 0.75×,
keeping the pitch), a sleep timer (15 to 60 minutes, or the end of the episode,
which also stops it going on into Up Next), AirPlay, the chapter list and the
transcript, which follows along and jumps where you tap. Audio keeps playing in
the background and shows on the Lock Screen and in Control Center, whose buttons
and headphones work too (on Mac, in Control Center's Now Playing and on the
media keys); video plays in the player, full screen or in picture in picture.

The position is saved on the server every 15 seconds and when you pause or stop,
so playback resumes where you left off here or in any other pressbox client.

Search is in the item list. Opened articles, and the content of up to 30 unread
items per refresh, are saved for offline reading. The token is kept in the
keychain on this device only; it is readable after the first unlock (rather than
behind Face ID) so the badge can update in the background.

## Development

```sh
just           # list the recipes
just fmt       # swift-format and the other formatters (devfmt's treefmt setup)
just verify    # check formatting, then nix flake check (formatting, reuse lint)
```

Changes are recorded in [CHANGELOG.md](CHANGELOG.md). Versions are calendar
versions, `YYYY.M.PATCH` (2026.11.0, then 2026.11.1, 2026.12.0). A release sets
`MARKETING_VERSION` in `project.yml` to it and `CURRENT_PROJECT_VERSION` to the
same as digits, `YYYYMMPP` (20261100), and is tagged `vYYYY.M.PATCH`.

## License

pressbox-darwin is [REUSE](https://reuse.software) compliant; every file states
its license in an SPDX header (`reuse lint` checks this, also in
`nix flake check`).

- The app, build files and docs are licensed under the
  [Mozilla Public License 2.0](LICENSES/MPL-2.0.txt). It keeps changes to its
  files open while allowing distribution through the App Store, which the GPL
  does not.
- The app icon (`assets/app-icon.svg` and the rendered `AppIcon.png`) is
  licensed under
  [Creative Commons Attribution-ShareAlike 4.0](LICENSES/CC-BY-SA-4.0.txt).

### Name and logo

The pressbox name and logo identify the pressbox project. The licenses above
cover copyright, not trademarks: you're welcome to use the logo to refer to
pressbox, but forks and derived apps must use their own name and icon.
