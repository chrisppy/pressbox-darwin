// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import SwiftUI

// Tiles for the feed list and the item lists: a grid that fits as many
// columns as the width allows, two or three on iPhone and more on iPad and
// Mac.

enum Tiles {
  /// Feeds, tags, All and Starred.
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

/// A square tile with its text on it: the artwork with the text over a
/// shade at the bottom, or, with no artwork (until it loads, or if it
/// can't), a plain tile with a symbol and the text.
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

  private var plainTile: some View {
    VStack(alignment: .leading, spacing: 0) {
      Image(systemName: symbol)
        .font(.title3)
        .foregroundStyle(tint)
        .padding([.top, .horizontal], 10)
        .accessibilityHidden(true)
      Spacer(minLength: 0)
      text(titleFont: .headline, lines: 4)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
