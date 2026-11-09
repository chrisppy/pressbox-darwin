<!--
SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
SPDX-License-Identifier: MPL-2.0
-->

# Changelog

All notable changes to pressbox-ios. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/). The app is versioned on its own; it
talks to pressbox servers through API v1 (`/api/v1`).

## [Unreleased]

- Tags: the feed list has a Tags section, one row per tag in the server's
  config with its unread count, showing the items of every feed with that tag.
  Mark all as read works there too.
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

## [0.1.0] - 2026-11-07

The first release.

- Feeds, item lists and an article reader for a pressbox server (SwiftUI, iOS
  18+), with search and offline reading.
- Pairing with a short code, and approving other devices (for any user, as an
  admin).
- Face ID lock, unread badge with background refresh, and mark as read on scroll
  (off by default).

[0.1.0]: https://github.com/chrisppy/pressbox-ios/releases/tag/v0.1.0
