// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import SwiftUI

struct FeedListView: View {
  @Environment(Store.self) private var store
  @Binding var showSettings: Bool
  @State private var showUpNext = false

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 20) {
        LazyVGrid(columns: Tiles.sources, spacing: Tiles.spacing) {
          SourceTile(
            title: store.title(for: .all), symbol: "tray.full",
            unread: store.unread(in: .all), source: .all)
          SourceTile(title: "Starred", symbol: "star", tint: Theme.star, source: .starred)
          if store.hasQueue {
            Button {
              showUpNext = true
            } label: {
              TileLabel(
                title: "Up Next", symbol: NowPlayingView.upNextSymbol, tint: .accentColor,
                count: store.queue.count)
            }
            .buttonStyle(.plain)
          }
        }
        if !store.tags.isEmpty {
          section("Tags") {
            ForEach(store.tags, id: \.self) { tag in
              SourceTile(
                title: tag, symbol: "tag", unread: store.unread(tagged: tag), source: .tag(tag))
            }
          }
        }
        section("Feeds") {
          ForEach(store.shownFeeds) { feed in
            SourceTile(feed: feed, unread: feed.unread(in: store.shows))
          }
        }
        // A list with no feeds at all: the tiles above stay, so a note here
        // rather than a full-screen empty state.
        if store.shownFeeds.isEmpty && !store.feeds.isEmpty {
          note(store.shows.podcasts ? "No podcasts yet." : "No news feeds yet.")
        } else if store.feeds.isEmpty && !store.isLoading {
          note(
            store.isOffline
              ? "Feeds show up once the server can be reached."
              : "No feeds yet. Add some to your pressbox server's config, or import an OPML file there, then refresh."
          )
        }
        let archived = store.feeds.filter(\.isArchived)
        if !archived.isEmpty {
          section("Removed Feeds") {
            ForEach(archived) { feed in
              SourceTile(feed: feed, unread: 0)
                .opacity(0.6)
            }
          }
          note("No longer in the server's config. Kept until you unstar their items.")
        }
      }
      .padding()
    }
    .themedScreen()
    .sheet(isPresented: $showUpNext) {
      UpNextView()
    }
    .navigationTitle("pressbox")
    .refreshable { await store.reload() }
    .onChange(of: store.source) { _, source in
      Task { await store.select(source) }
    }
    .bottomControls {
      Button("Settings", systemImage: "gear") { showSettings = true }
      // Servers before 26.0 don't say which feeds are podcasts.
      if store.canFilterKinds {
        kindToggles(store)
      }
      Button("Refresh Feeds", systemImage: "arrow.clockwise") {
        Task { await store.refreshServer() }
      }
      .disabled(store.isLoading)
    }
  }
}

extension FeedListView {
  private func section<Content: View>(
    _ title: LocalizedStringKey, @ViewBuilder tiles: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.headline)
        .foregroundStyle(.secondary)
        .accessibilityAddTraits(.isHeader)
      LazyVGrid(columns: Tiles.sources, spacing: Tiles.spacing) {
        tiles()
      }
    }
  }

  private func note(_ text: String) -> some View {
    Text(text)
      .font(.callout)
      .foregroundStyle(.secondary)
  }
}

/// A tile that opens a list: All, Starred, a tag or a feed.
private struct SourceTile: View {
  @Environment(Store.self) private var store
  let title: String
  var symbol = "dot.radiowaves.up.forward"
  var tint: Color = .secondary
  var image: URL?
  var unread = 0
  var error: String?
  let source: Source

  init(
    title: String, symbol: String, tint: Color = .secondary, unread: Int = 0, source: Source
  ) {
    self.title = title
    self.symbol = symbol
    self.tint = tint
    self.unread = unread
    self.source = source
  }

  init(feed: Feed, unread: Int) {
    title = feed.title
    symbol = feed.hasEpisodes && !feed.hasNews ? "waveform" : "newspaper"
    image = feed.image.flatMap(URL.init(string:))
    self.unread = unread
    error = feed.lastError
    source = .feed(feed.id)
  }

  var body: some View {
    Button {
      store.source = source
    } label: {
      TileLabel(
        title: title, symbol: symbol, tint: tint, image: image, count: unread, error: error)
    }
    .buttonStyle(.plain)
    .tileSelected(store.source == source)
  }
}

/// Artwork with a count in its corner, and the title under it.
private struct TileLabel: View {
  let title: String
  let symbol: String
  var tint: Color = .secondary
  var image: URL?
  var count = 0
  var error: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      TileArtwork(url: image, symbol: symbol, tint: tint)
        .overlay(alignment: .topTrailing) { TileBadge(count: count) }
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        if let error {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(Theme.error)
            .accessibilityLabel("Last fetch failed: \(error)")
        }
        Text(title)
          .font(.subheadline)
          .lineLimit(2, reservesSpace: true)
          .multilineTextAlignment(.leading)
      }
    }
    .contentShape(.rect)
    .accessibilityElement(children: .combine)
    .accessibilityValue(count > 0 ? "\(count) unread" : "")
  }
}
