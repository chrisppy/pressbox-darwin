// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import SwiftUI

struct ItemListView: View {
  @Environment(Store.self) private var store
  @Binding var selection: Item.ID?
  @State private var query = ""
  /// Rows on screen, and whether the user is scrolling, for marking items
  /// read as they scroll off the top.
  @State private var visible: Set<Item.ID> = []
  @State private var isScrolling = false
  @State private var confirmMarkAll = false

  var body: some View {
    List(selection: $selection) {
      ForEach(store.items) { item in
        ItemRow(item: item, feedTitle: store.feedTitle(item.feedId))
          .swipeActions(edge: .leading) {
            Button(
              item.read ? "Unread" : "Read",
              systemImage: item.read ? "circle.fill" : "circle"
            ) {
              Task { await store.setRead(item, !item.read) }
            }
            .tint(Theme.read)
          }
          .swipeActions(edge: .trailing) {
            Button(
              item.starred ? "Unstar" : "Star",
              systemImage: item.starred ? "star.slash" : "star"
            ) {
              Task { await store.setStarred(item, !item.starred) }
            }
            .tint(Theme.star)
            if item.isEpisode && store.hasQueue {
              let queued = store.isQueued(item)
              Button(
                queued ? "Remove from Up Next" : "Up Next",
                systemImage: queued ? "text.badge.minus" : "text.badge.plus"
              ) {
                Task {
                  if queued {
                    await store.dequeue(item)
                  } else {
                    await store.enqueue(item)
                  }
                }
              }
              .tint(Theme.upNext)
            }
          }
          .contextMenu {
            if item.isEpisode && store.hasQueue {
              Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                Task { await store.enqueue(item, next: true) }
              }
              Button("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") {
                Task { await store.enqueue(item) }
              }
              if store.isQueued(item) {
                Button("Remove from Up Next", systemImage: "minus.circle") {
                  Task { await store.dequeue(item) }
                }
              }
            }
          }
          .onAppear {
            visible.insert(item.id)
            Task { await store.loadMoreIfNeeded(after: item) }
          }
          .onDisappear {
            visible.remove(item.id)
            scrolledAway(item)
          }
      }
    }
    .listStyle(.plain)
    .themedScreen()
    .onScrollPhaseChange { _, phase in isScrolling = phase.isScrolling }
    .navigationTitle(store.source.map(store.title(for:)) ?? "")
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    .searchable(text: $query, prompt: "Search titles and text")
    .onSubmit(of: .search) {
      Task { await store.setSearch(query) }
    }
    .onChange(of: query) { _, text in
      if text.isEmpty, store.search != nil {
        Task { await store.setSearch(nil) }
      }
    }
    .refreshable { await store.reload() }
    .overlay {
      if store.items.isEmpty && !store.isLoading {
        if let search = store.search {
          ContentUnavailableView.search(text: search)
        } else {
          ContentUnavailableView(
            store.unreadOnly ? "All caught up" : "No items",
            systemImage: "checkmark.circle")
        }
      }
    }
    .safeAreaInset(edge: .bottom) {
      if store.isOffline {
        Label(
          store.outbox.isEmpty
            ? "Offline: showing saved items" : "Offline: changes will sync when you're back",
          systemImage: "wifi.slash"
        )
        .font(.footnote)
        .statusBanner()
      } else if let message = store.errorMessage {
        Text(message)
          .font(.footnote)
          .foregroundStyle(.white)
          .statusBanner(tint: Theme.error)
      }
    }
    .bottomControls(search: true) {
      // On: unread items only; off: all of them.
      Toggle(
        isOn: Binding(
          get: { store.unreadOnly },
          set: { value in Task { await store.setUnreadOnly(value) } })
      ) {
        Label(
          "Unread only",
          systemImage: store.unreadOnly
            ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
      }
      .toggleStyle(.button)
      .disabled(store.source == .starred)
    }
    // Up top, away from the thumb, and asking first: it can't be undone.
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("Mark all as read", systemImage: "checkmark.circle") { confirmMarkAll = true }
          .disabled(markAllCount == 0)
      }
    }
    .confirmationDialog(
      markAllTitle, isPresented: $confirmMarkAll, titleVisibility: .visible
    ) {
      Button("Mark \(markAllCount) as Read", role: .destructive) {
        Task { await store.markAllRead() }
      }
    } message: {
      Text("This can't be undone.")
    }
  }
}

extension ItemListView {
  /// The unread items Mark all as read would mark.
  private var markAllCount: Int { store.source.map(store.unread(in:)) ?? 0 }

  private var markAllTitle: String {
    let list = store.source.map(store.title(for:)) ?? ""
    return markAllCount == 1
      ? "Mark the unread item in \(list) as read?"
      : "Mark all \(markAllCount) unread items in \(list) as read?"
  }

  /// Marks an item read if it left the screen off the top: the user is
  /// scrolling and rows below it are still showing. Rows leaving because the
  /// list itself goes away (opening an article) happen while not scrolling.
  private func scrolledAway(_ item: Item) {
    guard store.markReadOnScroll, isScrolling, !item.read, store.search == nil,
      let index = store.items.firstIndex(where: { $0.id == item.id })
    else { return }
    let below = store.items[(index + 1)...].contains { visible.contains($0.id) }
    if below {
      Task { await store.setRead(item, true) }
    }
  }
}

struct ItemRow: View {
  @Environment(Store.self) private var store
  let item: Item
  let feedTitle: String

  /// Playing, started, or an episode not started yet.
  private var episodeSymbol: String? {
    guard item.isEpisode else { return nil }
    if store.playback.isCurrent(item) { return "speaker.wave.2.fill" }
    return item.resumeAt > 0 ? "circle.lefthalf.filled" : "waveform"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        Circle()
          .fill(item.read ? .clear : Color.accentColor)
          .frame(width: 8, height: 8)
        Text(feedTitle)
          .lineLimit(1)
        Spacer()
        if let episodeSymbol {
          Image(systemName: episodeSymbol).foregroundStyle(Color.accentColor)
        }
        switch Downloads.shared.state(item.id) {
        case .saved:
          Image(systemName: "arrow.down.circle.fill").accessibilityLabel("Downloaded")
        case .downloading:
          Image(systemName: "arrow.down.circle.dotted").accessibilityLabel("Downloading")
        default:
          EmptyView()
        }
        if item.starred {
          Image(systemName: "star.fill").foregroundStyle(Theme.star)
        }
        Text(item.publishedDate, format: .relative(presentation: .numeric))
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      Text(item.title)
        .font(.body.weight(item.read ? .regular : .semibold))
        .foregroundStyle(item.read ? .secondary : .primary)
        .lineLimit(3)
    }
    .padding(.vertical, 2)
  }
}
