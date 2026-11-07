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

# Build for the simulator without signing, as CI does (macOS)
build: project
    xcodebuild build -project Pressbox.xcodeproj -scheme Pressbox -destination 'generic/platform=iOS Simulator' -configuration Debug CODE_SIGNING_ALLOWED=NO

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
