// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import SwiftUI

// Liquid Glass on iOS and macOS 26, and the look the app had before on
// iOS 18 and macOS 15. System
// parts (navigation bars, toolbars, the search field, sidebars, sheets) turn
// to glass on their own when built with the iOS 26 SDK; these cover the
// app's own surfaces.

extension View {
  /// A status message floating over the bottom of a list: a glass capsule,
  /// tinted for errors. Before iOS 26, a full-width bar.
  func statusBanner(tint: Color? = nil) -> some View {
    modifier(StatusBanner(tint: tint))
  }

  /// The main action on a screen.
  @ViewBuilder func prominentButtonStyle() -> some View {
    if #available(iOS 26, macOS 26, *) {
      buttonStyle(.glassProminent)
    } else {
      buttonStyle(.borderedProminent)
    }
  }

  /// A secondary action set apart from the text beside it.
  @ViewBuilder func secondaryButtonStyle() -> some View {
    if #available(iOS 26, macOS 26, *) {
      buttonStyle(.glass)
    } else {
      buttonStyle(.bordered)
    }
  }
}

private struct StatusBanner: ViewModifier {
  let tint: Color?

  @ViewBuilder func body(content: Content) -> some View {
    if #available(iOS 26, macOS 26, *) {
      content
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(glass, in: .capsule)
        .padding(.horizontal)
        .padding(.bottom, 8)
    } else if let tint {
      content
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(tint.gradient)
    } else {
      content
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial)
    }
  }

  @available(iOS 26, macOS 26, *)
  private var glass: Glass {
    if let tint { .regular.tint(tint) } else { .regular }
  }
}
