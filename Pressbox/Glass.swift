// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import SwiftUI

// Liquid Glass for the app's own surfaces. System parts (navigation bars,
// toolbars, the search field, sidebars, sheets) are glass on their own.

extension View {
  /// A status message floating over the bottom of a list: a glass capsule,
  /// tinted for errors.
  func statusBanner(tint: Color? = nil) -> some View {
    padding(.horizontal, 16)
      .padding(.vertical, 10)
      .glassEffect(tint.map { Glass.regular.tint($0) } ?? .regular, in: .capsule)
      .padding(.horizontal)
      .padding(.bottom, 8)
  }
}
