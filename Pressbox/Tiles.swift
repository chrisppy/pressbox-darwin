// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import SwiftUI

// Tiles for the feed list and the item lists: a grid that fits as many
// columns as the width allows, two or three on iPhone and more on iPad and
// Mac.

enum Tiles {
  /// Feeds, tags, All and Starred.
  /// Top-aligned: a tile with its title inside is shorter than one with the
  /// title under its artwork.
  static let sources = [
    GridItem(.adaptive(minimum: 104, maximum: 180), spacing: 12, alignment: .top)
  ]
  /// Articles and episodes.
  static let items = [
    GridItem(.adaptive(minimum: 160, maximum: 280), spacing: 12, alignment: .top)
  ]
  static let spacing: CGFloat = 12
  static let cornerRadius: CGFloat = 14
}

/// Square artwork from a URL. With none, or until it loads (or if it
/// can't), the tile shows the title itself, under a symbol.
struct TileArtwork: View {
  let url: URL?
  let symbol: String
  var tint: Color = .secondary
  let title: String

  var body: some View {
    Color.clear
      .aspectRatio(1, contentMode: .fit)
      .overlay {
        if let url {
          AsyncImage(url: url) { phase in
            if let image = phase.image {
              image.resizable().scaledToFill().accessibilityHidden(true)
            } else {
              titleTile
            }
          }
        } else {
          titleTile
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: Tiles.cornerRadius))
  }

  private var titleTile: some View {
    VStack(alignment: .leading, spacing: 4) {
      Image(systemName: symbol)
        .font(.title3)
        .foregroundStyle(tint)
        .accessibilityHidden(true)
      Spacer(minLength: 0)
      Text(title)
        .font(.headline)
        .foregroundStyle(.primary)
        .lineLimit(4)
        .minimumScaleFactor(0.75)
        .multilineTextAlignment(.leading)
    }
    .padding(10)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .background(.quaternary)
  }
}

/// A count in the corner of a tile, as `.badge` gives a list row: the
/// accent through glass, as a selected control in the bottom bar has it,
/// since the accent painted flat reads as red.
struct TileBadge: View {
  let count: Int

  var body: some View {
    if count > 0 {
      Text(count, format: .number)
        .font(.caption.bold().monospacedDigit())
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .glassEffect(.regular.tint(.accentColor), in: .capsule)
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
