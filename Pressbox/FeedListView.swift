// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import SwiftUI

struct FeedListView: View {
  @Environment(Store.self) private var store
  @Binding var showSettings: Bool
  @State private var showUpNext = false

  var body: some View {
    @Bindable var store = store
    List(selection: $store.source) {
      Section {
        NavigationLink(value: Source.all) {
          Label(store.title(for: .all), systemImage: "tray.full")
        }
        .badge(store.unread(in: .all))
        NavigationLink(value: Source.starred) {
          Label("Starred", systemImage: "star")
        }
        if store.hasQueue {
          Button {
            showUpNext = true
          } label: {
            Label("Up Next", systemImage: NowPlayingView.upNextSymbol)
          }
          .foregroundStyle(.primary)
          .badge(store.queue.count)
        }
      }
      if !store.tags.isEmpty {
        Section("Tags") {
          ForEach(store.tags, id: \.self) { tag in
            NavigationLink(value: Source.tag(tag)) {
              Label(tag, systemImage: "tag")
            }
            .badge(store.unread(tagged: tag))
          }
        }
      }
      Section("Feeds") {
        ForEach(store.shownFeeds) { feed in
          NavigationLink(value: Source.feed(feed.id)) {
            HStack {
              Text(feed.title)
              if let error = feed.lastError {
                Image(systemName: "exclamationmark.triangle.fill")
                  .foregroundStyle(Theme.error)
                  .accessibilityLabel("Last fetch failed: \(error)")
              }
            }
          }
          .badge(feed.unread(in: store.shows))
        }
        // A list with no feeds at all: the rows above stay, so a note here
        // rather than a full-screen empty state.
        if store.shownFeeds.isEmpty && !store.feeds.isEmpty {
          Text(store.shows.podcasts ? "No podcasts yet." : "No news feeds yet.")
            .font(.callout)
            .foregroundStyle(.secondary)
        } else if store.feeds.isEmpty && !store.isLoading {
          Text(
            store.isOffline
              ? "Feeds show up once the server can be reached."
              : "No feeds yet. Add some to your pressbox server's config, or import an OPML file there, then refresh."
          )
          .font(.callout)
          .foregroundStyle(.secondary)
        }
      }
      let archived = store.feeds.filter(\.isArchived)
      if !archived.isEmpty {
        Section {
          ForEach(archived) { feed in
            NavigationLink(value: Source.feed(feed.id)) {
              Text(feed.title).foregroundStyle(.secondary)
            }
          }
        } header: {
          Text("Removed Feeds")
        } footer: {
          Text("No longer in the server's config. Kept until you unstar their items.")
        }
      }
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
      // Servers before 2026.11 don't say which feeds are podcasts.
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
