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
    #!/usr/bin/env bash
    set -euo pipefail
    # SwiftPM's --enable-code-coverage wants llvm-profdata beside swift, which
    # nixpkgs' Swift lacks: instrument and merge by hand, with the devShell's
    # LLVM. Its own build path, so `just test` doesn't rebuild every time.
    out=.build/coverage
    flags=(--build-path "$out" -Xswiftc -profile-generate -Xswiftc -profile-coverage-mapping)
    rm -rf "$out/profiles"
    LLVM_PROFILE_FILE="$PWD/$out/profiles/%p.profraw" swift test "${flags[@]}"
    llvm-profdata merge -sparse "$out"/profiles/*.profraw -o "$out/coverage.profdata"
    # Every object file of the build: they carry the coverage mapping wherever
    # SwiftPM puts them (its layout changes between versions). The report
    # keeps Core/ and drops the tests and generated sources.
    mapfile -t objects < <(find "$out" -name '*.o' -type f)
    [ "${#objects[@]}" -gt 0 ] || { echo "no object files under $out" >&2; exit 1; }
    args=("${objects[0]}")
    for o in "${objects[@]:1}"; do args+=(-object "$o"); done
    llvm-cov report "${args[@]}" -instr-profile="$out/coverage.profdata" \
      -ignore-filename-regex='PressboxTests/|\.build/|/nix/store/'

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
