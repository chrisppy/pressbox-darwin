<!--
SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
SPDX-License-Identifier: MPL-2.0
-->

# pressbox-ios

The iOS app for [pressbox](https://github.com/chrisppy/pressbox), a self-hosted
feed reader whose feeds and users are declared in NixOS. It reads from your
pressbox server over its HTTP API (`/api/v1`) and shares read and starred state
with the other clients, such as the `pressbox` terminal reader.

> [!NOTE]
> pressbox-ios is in its early days. Expect rough edges, and features and
> behavior that may change between versions.

## Requirements

- iOS 18 or later.
- A pressbox server reachable over HTTPS. iOS only allows plain HTTP to local
  network addresses; `tailscale serve --bg 8470` on the server is the least
  work, and a reverse proxy with ACME works too.
- To build: a Mac with Xcode and
  [XcodeGen](https://github.com/yonaskolb/XcodeGen).

## Building

The repo holds an XcodeGen spec (`project.yml`) and the SwiftUI sources
(`Pressbox/`); the Xcode project is generated, not committed.

```sh
nix develop    # provides xcodegen on macOS, or: brew install xcodegen
just open      # xcodegen, then open Pressbox.xcodeproj
```

Set your team under Signing & Capabilities (or `DEVELOPMENT_TEAM` in
`project.yml`) and run it. CI builds the app for the simulator on every change
(`.github/workflows/ios.yml`); `just build` does the same locally.

## Using it

On first launch, enter the server address and tap "Pair this device". The app
shows a code like `K7W-4QX`: approve it on the server with
`sudo pressboxctl approve K7W-4QX`, or from a device that is already paired
(`pressbox approve K7W-4QX`). See pressbox's README for pairing and users.

Settings also has:

- **Approve a device**, for pairing other clients from your phone. Admins can
  approve a device for another user.
- **Require Face ID**, which locks the app whenever it goes to the background.
- **Mark as read when scrolled past**, off by default: items are marked read as
  they scroll off the top of the list while you scroll (not in search results).
- **Unread count on app icon**, kept current by background refresh.

The Server section shows the address, the signed-in user and device, and the
server's version.

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

Changes are recorded in [CHANGELOG.md](CHANGELOG.md). A release bumps
`MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION`) in `project.yml` and is
tagged `vX.Y.Z`.

## License

pressbox-ios is [REUSE](https://reuse.software) compliant; every file states its
license in an SPDX header (`reuse lint` checks this, also in `nix flake check`).

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
