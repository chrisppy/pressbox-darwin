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
    ScrollViewReader { proxy in
      List(selection: $selection) {
        ForEach(store.items) { item in
          ItemRow(item: item, feedTitle: store.feedTitle(item.feedId))
            .swipeActions(edge: .leading) {
              Button(
                item.read ? "Unread" : "Read",
                systemImage: item.read ? "circle.fill" : "circle"
              ) {
                store.haptic(.toggle)
                Task { await store.setRead(item, !item.read) }
              }
              .tint(Theme.read)
            }
            .swipeActions(edge: .trailing) {
              Button(
                item.starred ? "Unstar" : "Star",
                systemImage: item.starred ? "star.slash" : "star"
              ) {
                store.haptic(.toggle)
                Task { await store.setStarred(item, !item.starred) }
              }
              .tint(Theme.star)
              if item.isEpisode && store.hasQueue {
                let queued = store.isQueued(item)
                Button(
                  queued ? "Remove from Up Next" : "Up Next",
                  systemImage: queued ? "text.badge.minus" : "text.badge.plus"
                ) {
                  store.haptic(queued ? .toggle : .added)
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
      .onKeyPress(characters: Self.shortcutKeys, phases: .down) { press in
        shortcut(press, proxy: proxy)
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
        emptyState
      }
    }
    .safeAreaInset(edge: .bottom) {
      VStack(spacing: 0) {
        if let undoable = store.undoable {
          UndoToast(undoable: undoable)
        }
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
      .animation(.default, value: store.undoable?.id)
    }
    .bottomControls(search: true) {
      // On: unread items only; off: all of them. Starred shows every starred
      // item either way, so it has none.
      if store.source != .starred {
        Toggle(
          isOn: Binding(
            get: { store.unreadOnly },
            set: { value in Task { await store.setUnreadOnly(value) } })
        ) {
          // The unread dot, as on the rows: filled for unread only, an
          // outline for all.
          Label(
            store.unreadOnly ? "Unread only" : "All items",
            systemImage: store.unreadOnly ? "circle.fill" : "circle")
        }
        .toggleStyle(.button)
      }
      // News and Podcasts where a list spans every feed. A feed or tag's
      // list follows the choice made on the feed list.
      if store.canFilterKinds && (store.source == .all || store.source == .starred) {
        kindToggles(store)
      }
    }
    // Up top, away from the thumb, and asking first. Undo is only there for
    // a few seconds after.
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
        store.haptic(.done)
        Task { await store.markAllRead() }
      }
    } message: {
      Text("You can undo it for a few seconds after.")
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

  /// What an empty list says, and what to do about it.
  @ViewBuilder private var emptyState: some View {
    let list = store.source.map(store.title(for:)) ?? ""
    if let search = store.search {
      ContentUnavailableView.search(text: search)
    } else if store.isOffline {
      ContentUnavailableView(
        "Offline", systemImage: "wifi.slash",
        description: Text("Nothing in \(list) was saved to read offline."))
    } else if let message = store.errorMessage {
      ContentUnavailableView {
        Label("Couldn't Load \(list)", systemImage: "exclamationmark.triangle")
      } description: {
        Text(message)
      } actions: {
        Button("Try Again") { Task { await store.reload() } }
      }
    } else if store.source == .starred {
      ContentUnavailableView(
        "No starred items", systemImage: "star",
        description: Text(Self.starHint))
    } else if store.unreadOnly {
      ContentUnavailableView {
        Label("All caught up", systemImage: "checkmark.circle")
      } description: {
        Text("No unread items in \(list).")
      } actions: {
        Button("Show All Items") { Task { await store.setUnreadOnly(false) } }
      }
    } else {
      ContentUnavailableView(
        "No items", systemImage: "tray",
        description: Text(
          "Nothing in \(list) yet. New items show up as the server fetches its feeds."))
    }
  }

  #if os(macOS)
    private static let starHint = "Star an item from its toolbar to keep it here."
  #else
    private static let starHint = "Swipe left on an item, or use Star on its page, to keep it here."
  #endif

  /// Keys that act on the list when it has the keyboard focus (Mac, or an
  /// iPad with a keyboard). Typing in the search field doesn't reach them.
  private static let shortcutKeys = CharacterSet(charactersIn: "jkms ")

  /// j and k: the next and previous item; m: read or unread; s: star or
  /// unstar; space: play or pause, or play the selected episode.
  private func shortcut(_ press: KeyPress, proxy: ScrollViewProxy) -> KeyPress.Result {
    // Leave ⌘S and the like to the menus.
    guard press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }
    let index = selection.flatMap { id in store.items.firstIndex { $0.id == id } }
    let current = index.map { store.items[$0] }
    switch press.characters {
    case "j", "k":
      let next = press.characters == "j" ? (index.map { $0 + 1 } ?? 0) : (index.map { $0 - 1 } ?? 0)
      guard store.items.indices.contains(next) else { return .handled }
      let id = store.items[next].id
      selection = id
      withAnimation { proxy.scrollTo(id) }
    case "m":
      guard let current else { return .ignored }
      Task { await store.setRead(current, !current.read) }
    case "s":
      guard let current else { return .ignored }
      Task { await store.setStarred(current, !current.starred) }
    case " ":
      if store.playback.item != nil {
        store.playback.togglePause()
      } else if let current, current.isEpisode {
        Task { await store.playback.play(current) }
      } else {
        return .ignored
      }
    default:
      return .ignored
    }
    return .handled
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
      Task { await store.markReadScrolledPast(item) }
    }
  }
}

/// Undo for marking items read in bulk: Mark all as read, or scrolling.
/// It goes by itself after a few seconds (`Store.undoSeconds`).
private struct UndoToast: View {
  @Environment(Store.self) private var store
  let undoable: Undoable

  var body: some View {
    HStack(spacing: 16) {
      Text(undoable.message)
      Button("Undo") { Task { await store.undo() } }
        .bold()
        // ⌘Z on Mac, and on iPad with a keyboard.
        .keyboardShortcut("z")
    }
    .font(.footnote)
    .statusBanner()
    .transition(.move(edge: .bottom).combined(with: .opacity))
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
