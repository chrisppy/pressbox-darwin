# SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
# SPDX-License-Identifier: MPL-2.0

set dotenv-load := false

# List available recipes
default:
    @just --list

# Generate Pressbox.xcodeproj from project.yml (macOS)
project:
    xcodegen

# Generate the project and open it in Xcode (macOS)
open: project
    open Pressbox.xcodeproj

# Build for the iOS simulator and for macOS without signing, as CI does (macOS)
build: build-ios build-mac

# Build for the iOS simulator (iPhone and iPad) without signing (macOS)
build-ios: project
    xcodebuild build -project Pressbox.xcodeproj -scheme Pressbox -destination 'generic/platform=iOS Simulator' -configuration Debug CODE_SIGNING_ALLOWED=NO

# Build the Mac app without signing (macOS)
build-mac: project
    xcodebuild build -project Pressbox.xcodeproj -scheme Pressbox -destination 'generic/platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO

# Run the unit tests of Core/ with SwiftPM: no Xcode or simulator (Linux or macOS)
test:
    swift test

# The same, then a line-coverage report of Core/ (Linux; on macOS use `xcrun llvm-cov`)
coverage:
    swift test --enable-code-coverage
    llvm-cov report "$(swift build --show-bin-path)/PressboxPackageTests.xctest" -instr-profile="$(swift build --show-bin-path)/codecov/default.profdata" -ignore-filename-regex='PressboxTests|\.build'

# Run all the unit tests in an iPhone simulator, widgets' included (macOS)
test-app: project
    xcodebuild test -project Pressbox.xcodeproj -scheme Pressbox -destination "id=$(xcrun simctl list devices available --json | jq -r '[.devices[][] | select(.name | startswith("iPhone"))][0].udid')" -configuration Debug CODE_SIGNING_ALLOWED=NO

# Check formatting and licensing
check:
    nix flake check

# Format Swift, Nix and the other configured files
fmt:
    nix fmt

# Check formatting without modifying files (the flake's treefmt check, run on a copy)
fmt-check:
    nix build --no-link ".#checks.$(nix eval --impure --raw --expr builtins.currentSystem).treefmt"

# Update all flake inputs
update:
    nix flake update

# Check formatting and the flake
verify: fmt-check check
