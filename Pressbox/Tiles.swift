// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import SwiftUI

// Tiles for the feed list and the item lists: a grid that fits as many
// columns as the width allows: three on iPhone and more on iPad and Mac.

enum Tiles {
  /// Between tiles, across and down.
  static let spacing: CGFloat = 16
  /// Feeds, tags, All and Starred. At least 100 points, so three fit across
  /// even the narrowest iPhone (343 points inside the margins) with the
  /// spacing between them.
  static let sources = [
    GridItem(.adaptive(minimum: 100, maximum: 180), spacing: spacing, alignment: .top)
  ]
  /// Articles and episodes: three across on every iPhone, as the feeds are.
  static let items = [
    GridItem(.adaptive(minimum: 100, maximum: 220), spacing: spacing, alignment: .top)
  ]
  static let cornerRadius: CGFloat = 14
}

/// A square tile with its text on it: the artwork with the text over a
/// shade at the bottom, or, with no artwork (until it loads, or if it
/// can't), a plain tile with a large symbol over the text.
struct TileArtwork: View {
  let url: URL?
  let symbol: String
  var tint: Color = .secondary
  let title: String
  /// A line above the title: an item's feed and age.
  var detail: Text?
  /// The dot of an unread item, beside the detail.
  var unread = false
  /// A bolder title, for unread items.
  var emphasized = false

  var body: some View {
    Color.clear
      .aspectRatio(1, contentMode: .fit)
      .overlay {
        if let url {
          AsyncImage(url: url) { phase in
            if let image = phase.image {
              image.resizable().scaledToFill().accessibilityHidden(true)
                .overlay(alignment: .bottom) { shadedText }
            } else {
              plainTile
            }
          }
        } else {
          plainTile
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: Tiles.cornerRadius))
  }

  /// White text over the artwork, on a shade that darkens toward the
  /// bottom so it reads on any picture.
  private var shadedText: some View {
    text(titleFont: .subheadline, lines: 3)
      .foregroundStyle(.white)
      .padding(.top, 24)
      .background(
        LinearGradient(
          colors: [.clear, .black.opacity(0.55), .black.opacity(0.8)],
          startPoint: .top, endPoint: .bottom))
  }

  /// The symbol large in the middle, as the tile's picture, and the text
  /// under it.
  private var plainTile: some View {
    VStack(spacing: 0) {
      Spacer(minLength: 6)
      Image(systemName: symbol)
        .font(.system(size: 34))
        .foregroundStyle(tint)
        .accessibilityHidden(true)
      Spacer(minLength: 4)
      text(titleFont: .subheadline, lines: 2)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.quaternary)
  }

  private func text(titleFont: Font, lines: Int) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      if let detail {
        HStack(spacing: 4) {
          if unread {
            Circle()
              .fill(Color.accentColor)
              .frame(width: 7, height: 7)
              .accessibilityLabel("Unread")
          }
          detail.lineLimit(1)
        }
        .font(.caption2)
        .opacity(0.85)
      }
      Text(title)
        .font(titleFont.weight(emphasized ? .bold : .semibold))
        .lineLimit(lines)
        .minimumScaleFactor(0.75)
        .multilineTextAlignment(.leading)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
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
