// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import SwiftUI

// Tiles for the feed list and the item lists: a grid that fits as many
// columns as the width allows, two or three on iPhone and more on iPad and
// Mac.

enum Tiles {
  /// Feeds, tags, All and Starred.
  static let sources = [GridItem(.adaptive(minimum: 104, maximum: 180), spacing: 12)]
  /// Articles and episodes.
  static let items = [GridItem(.adaptive(minimum: 160, maximum: 280), spacing: 12)]
  static let spacing: CGFloat = 12
  static let cornerRadius: CGFloat = 14
}

/// Square artwork from a URL, or a symbol on a plain tile when there is
/// none or it hasn't loaded.
struct TileArtwork: View {
  let url: URL?
  let symbol: String
  var tint: Color = .secondary

  var body: some View {
    Color.clear
      .aspectRatio(1, contentMode: .fit)
      .overlay {
        if let url {
          AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
          } placeholder: {
            placeholder
          }
        } else {
          placeholder
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: Tiles.cornerRadius))
      .accessibilityHidden(true)
  }

  private var placeholder: some View {
    Image(systemName: symbol)
      .font(.largeTitle)
      .foregroundStyle(tint)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(.quaternary)
  }
}

/// A count in the corner of a tile, as `.badge` gives a list row.
struct TileBadge: View {
  let count: Int

  var body: some View {
    if count > 0 {
      Text(count, format: .number)
        .font(.caption.bold().monospacedDigit())
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.accentColor, in: .capsule)
        .padding(6)
    }
  }
}

extension View {
  /// The ring round a selected tile, where a list would highlight the row.
  func tileSelected(_ selected: Bool) -> some View {
    overlay {
      RoundedRectangle(cornerRadius: Tiles.cornerRadius + 4)
        .strokeBorder(Color.accentColor, lineWidth: 3)
        .padding(-4)
        .opacity(selected ? 1 : 0)
    }
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}
