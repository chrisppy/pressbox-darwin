// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import SwiftUI

struct FeedListView: View {
  @Environment(Store.self) private var store
  @Binding var showSettings: Bool

  var body: some View {
    @Bindable var store = store
    List(selection: $store.source) {
      Section {
        NavigationLink(value: Source.all) {
          Label("All items", systemImage: "tray.full")
        }
        .badge(store.totalUnread)
        NavigationLink(value: Source.starred) {
          Label("Starred", systemImage: "star")
        }
      }
      Section("Feeds") {
        ForEach(store.feeds.filter { !$0.isArchived }) { feed in
          NavigationLink(value: Source.feed(feed.id)) {
            HStack {
              Text(feed.title)
              if let error = feed.lastError {
                Image(systemName: "exclamationmark.triangle.fill")
                  .foregroundStyle(.red)
                  .accessibilityLabel("Last fetch failed: \(error)")
              }
            }
          }
          .badge(feed.unread)
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
          Text("Removed feeds")
        } footer: {
          Text("No longer in the server's config. Kept until you unstar their items.")
        }
      }
    }
    .navigationTitle("pressbox")
    .refreshable { await store.reload() }
    .onChange(of: store.source) { _, source in
      Task { await store.select(source) }
    }
    .bottomControls {
      Button("Settings", systemImage: "gear") { showSettings = true }
      Button("Refresh feeds", systemImage: "arrow.clockwise") {
        Task { await store.refreshServer() }
      }
      .disabled(store.isLoading)
    }
  }
}
