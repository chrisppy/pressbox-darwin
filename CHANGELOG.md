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

- The logic with no screens is in `Core/`, which also builds as a Swift package:
  `just test` runs its unit tests with `swift test` on Linux or a Mac, and CI
  runs them on Linux too. `just test-app` runs all the tests in the iOS
  simulator, as `just test` did before.
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
  reach: Settings and Refresh under the feeds; an Unread only toggle under the
  items, with search beside it (moved down on iOS 26); star, read, share and
  Safari under an article, and under an episode Play, Up Next, Download and a
  More menu with the rest: Watch Video, Chapters and Transcript when the episode
  has them, then star, read, share and Safari. An episode has no header above
  it; its length, number and where it was left are in its byline. On iPhone,
  Back (and Home, to the feed list, from an article) lead the group; the feed
  list has neither. Swiping from the edge still goes back.
- Changes made offline are kept and sent later: marking items read or unread,
  starring, podcast positions, and an episode finishing while offline (which
  used to leave it unread). They show in the app at once, wait on disk while the
  server can't be reached, and are sent before the next reload. The offline
  banner says when changes are waiting.
- Up Next (needs a pressbox server with a queue): episodes to play one after
  another, kept on the server so every client shares it. Add an episode by
  swiping its row, from its context menu (Play Next or Play Last), or with the
  button in its bottom bar; open Up Next from the feed list or the full player
  to play, reorder or remove. When an episode ends, the first one in Up Next
  starts, and finished episodes leave it. Changes made offline are sent later,
  like the rest.
- Downloads, to play episodes offline: the audio of the 10 newest unread
  episodes downloads automatically, and any episode's audio or video from its
  page. Settings chooses Wi-Fi only (the default) or Wi-Fi and cellular, shows
  the space used and removes everything. Downloads go once an episode is
  finished or read, anywhere, and automatic ones once they leave the 10 newest
  unread. They use a background session, so they finish with the app closed.
- Widgets: Unread (the count, and the newest unread items; on the Lock Screen
  too) and Up Next (the episode playing or next, with a play/pause button that
  works without opening the app, and what follows). The app shares what they
  show through the App Group `group.org.red-oxide.pressbox`, and background
  refresh now runs whenever a server is set, to keep them current, not only for
  the badge. Items open from the widgets with `pressbox://item/ID` links.
- Mark all as read moved from the items' bottom bar to the top, out of easy
  reach, and asks first, saying how many items it will mark.
- The mini player stays off an episode's page, whose bottom bar already has
  Play; its More menu opens the full player (Now Playing) instead. On an iPad
  with the columns side by side, the mini player moves under the item list.
- A sleep timer in the full player: 15, 30, 45 or 60 minutes, or the end of the
  episode (which also stops it going on into Up Next).
- Siri and Shortcuts: play or pause (or play Up Next), skip forward and skip
  back, with phrases that need no setup, and so on the Action button too; and a
  play/pause control for Control Center on iPhone and iPad.
- An About section at the bottom of Settings: the app's version and build (to
  tell TestFlight builds apart), and links to the source code, the changelog,
  red-oxide.org and the license.
- The unread badge says when the system is hiding it: with Badges (or all
  notifications) turned off for pressbox in the Settings app, setting the count
  silently did nothing. Settings now shows a warning under the badge switch,
  with a button to the right page in the Settings app (on Mac, where to find it
  in System Settings). The check runs on every reload and when Settings opens.
- Haptics on iPhone for what you do by hand: a tick for read or unread and star
  or unstar (swipes and the article's buttons), a light tap for adding to Up
  Next, and a success buzz for Mark all as read. Items marked read by scrolling
  stay quiet.
- Undo after marking items read in bulk: a toast at the bottom of the list says
  how many were marked, with Undo (⌘Z on Mac and on an iPad keyboard) for 6
  seconds. Mark all as read is done in the app at once and sent to the server
  when the toast goes (or before anything else loads, or when the app goes to
  the background), so Undo doesn't need the server. Items marked read by
  scrolling add up in one toast while you keep scrolling. Mark all as read still
  asks first.
- Podcast settings: how far the skip buttons jump, back and forward (5 to 60
  seconds; also on the Lock Screen, in Control Center and for Siri and
  Shortcuts), and a default speed. Each podcast keeps its own speed: change it
  in the player and that podcast's episodes play at it from then on; set it back
  to the default to forget it. Speeds are kept on this device.
- Keyboard shortcuts in the item list, on Mac and on an iPad with a keyboard: j
  and k for the next and previous item, m for read or unread, s to star or
  unstar, and space to play or pause (or play the selected episode). They work
  while the list has the focus (click it, or Tab to it), so typing in the search
  field isn't affected.
- Picks up where you left off: when iOS closes pressbox in the background, it
  reopens to the same list and item (swiping it away in the app switcher still
  starts afresh). On iPhone and iPad, articles and episode pages also reopen
  where they were scrolled to, at any time; the 200 most recent are kept on the
  device.
- Empty lists say why, and what to do: Starred says how to star items; All
  caught up offers Show All Items; an empty list offline, or one that failed to
  load, says so (with Try Again) instead of looking caught up; and a server with
  no feeds yet says where to add them.
- Settings shows whether the server is connected, at the top of its Server
  section: a green Connected with when it last answered, a yellow Offline with
  how many changes are waiting to sync, or a red problem such as a rejected
  token, a server error or a server that can't be found. Check Now asks again;
  opening Settings checks too.
- News and Podcasts toggles in the feed list's bottom bar (needs a pressbox
  server that counts episodes, 2026.11): both on shows everything; one on shows
  only news or only podcast episodes, in every list, with unread counts to
  match, and hides feeds with nothing of that kind. Turning off the only one on
  switches to the other. Mark all as read marks only the kind shown. The badge
  and the widgets still count everything.

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
