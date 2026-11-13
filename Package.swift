// swift-tools-version: 6.0
// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

// The app's logic in Core/, as a package, so its tests run with `swift test`
// on Linux as well as on a Mac, without Xcode or a simulator. The app itself
// builds from project.yml, which compiles Core/ into the app; this package is
// only for the tests.

import PackageDescription

let package = Package(
  name: "Pressbox",
  platforms: [.iOS("27.0"), .macOS("27.0")],
  targets: [
    // Named like the app, so the tests' `@testable import Pressbox` works in
    // both.
    .target(name: "Pressbox", path: "Core"),
    .testTarget(name: "PressboxTests", dependencies: ["Pressbox"], path: "PressboxTests"),
  ],
  // As in project.yml.
  swiftLanguageModes: [.v5]
)
