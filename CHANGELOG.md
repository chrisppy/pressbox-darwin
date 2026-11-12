<!--
SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
SPDX-License-Identifier: MPL-2.0
-->

# Changelog

All notable changes to pressbox-darwin (formerly pressbox-ios). The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions
are [calendar versions](https://calver.org/), `YYYY.M.PATCH`: the year and month
of the release, then a count that starts at 0 each month (2026.11.0, 2026.11.1,
2026.12.0). The app is versioned on its own; it talks to pressbox servers
through API v1 (`/api/v1`).

## [2026.11.0] - Unreleased

- A Mac app (macOS 15 or later) from the same target and sources as the iPhone
  and iPad app, and the repository is renamed pressbox-darwin. On Mac the
  controls are in the window toolbar, search is in the title bar, Settings is
  its own window (⌘,), Reload is ⌘R, links open in the default browser, and the
  lock uses Touch ID. With no background refresh on macOS, the app reloads every
  15 minutes while open to keep the Dock badge current. The app runs in the App
  Sandbox and keeps its token in the data protection keychain. CI builds both
  platforms.
- Podcasts (needs a pressbox server with podcast support): episodes play with
  AVPlayer, resume where any client left off (the position syncs every 15
  seconds and on pause and stop) and are marked read when played to the end. A
  mini player above every screen's controls opens a full player with scrubbing,
  10/30-second skips, chapters, speeds that keep the pitch, AirPlay and the
  transcript, which follows along. Audio plays in the background with Lock
  Screen and Control Center controls (on Mac, Now Playing and the media keys);
  video plays inline, full screen or in picture in picture. Opening an episode
  no longer marks it read.
- Tags: the feed list has a Tags section, one row per tag in the server's config
  with its unread count, showing the items of every feed with that tag. Mark all
  as read works there too.
- Item lists show their title small and inline instead of as a large title.
- Birdland colors throughout: Orioles orange as the tint, Birdland backgrounds
  and text in dark mode and Birdland Light in light mode, brass stars, a Camden
  green read action, and article text and links in the same palette. The colors
  are color sets in `Assets.xcassets`, and `Theme.swift` maps them to their
  uses.
- Item lists page by cursor, which stays fast far down a long list; older
  servers without cursors are paged by offset as before.
- Liquid Glass on iOS 26: the offline and error banners float as glass capsules,
  the Unlock and Approve buttons use glass styles, and the article toolbar
  splits into two glass groups. Navigation bars, toolbars, search and the
  sidebar pick it up from the system. iOS 18 looks as before. Building now needs
  Xcode 26.
- Controls are grouped together in the middle of a bottom toolbar, within thumb
  reach: Settings and Refresh under the feeds; Mark all as read and the
  Unread/All filter under the items, with search beside them (moved down on iOS
  26); star, read, share and Safari under an article. On iPhone, Back (and Home,
  to the feed list, from an article) lead the group; the feed list has neither.
  Swiping from the edge still goes back.
- Changes made offline are kept and sent later: marking items read or unread,
  starring, podcast positions, and an episode finishing while offline (which
  used to leave it unread). They show in the app at once, wait on disk while the
  server can't be reached, and are sent before the next reload. The offline
  banner says when changes are waiting.
- Up Next (needs a pressbox server with a queue): episodes to play one after
  another, kept on the server so every client shares it. Add an episode by
  swiping its row, from its context menu (Play Next or Play Last), or with the
  button above it; open Up Next from the feed list or the full player to play,
  reorder or remove. When an episode ends, the first one in Up Next starts, and
  finished episodes leave it. Changes made offline are sent later, like the
  rest.
- An About section at the bottom of Settings: the app's version and build (to
  tell TestFlight builds apart), and links to the source code, the changelog,
  red-oxide.org and the license.

## [0.1.0] - 2026-11-07

The first release.

- Feeds, item lists and an article reader for a pressbox server (SwiftUI, iOS
  18+), with search and offline reading.
- Pairing with a short code, and approving other devices (for any user, as an
  admin).
- Face ID lock, unread badge with background refresh, and mark as read on scroll
  (off by default).

[0.1.0]: https://github.com/chrisppy/pressbox-ios/releases/tag/v0.1.0
[2026.11.0]: https://github.com/red-oxide/pressbox-darwin/compare/v0.1.0...v2026.11.0
