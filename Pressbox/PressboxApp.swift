// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import SwiftUI

@main
struct PressboxApp: App {
  @State private var store = Store()

  var body: some Scene {
    #if os(macOS)
      WindowGroup {
        ContentView()
          .environment(store)
      }
      .commands { FeedCommands(store: store) }
      Settings {
        SettingsView()
          .environment(store)
      }
    #else
      WindowGroup {
        ContentView()
          .environment(store)
      }
      .backgroundTask(.appRefresh(Store.refreshTaskID)) {
        await Store.backgroundRefresh()
      }
      // Episode downloads that finished while the app was away.
      .backgroundTask(.urlSession(Downloads.sessionID)) {
        await Downloads.shared.handleBackgroundEvents()
      }
    #endif
  }
}

#if os(macOS)
  /// Menu commands for what pull-to-refresh and the toolbars do on iPhone.
  struct FeedCommands: Commands {
    let store: Store

    var body: some Commands {
      CommandGroup(after: .toolbar) {
        Button("Reload") {
          Task { await store.reload() }
        }
        .keyboardShortcut("r")
        .disabled(!store.isConfigured)
        Button("Refresh Feeds on Server") {
          Task { await store.refreshServer() }
        }
        .keyboardShortcut("r", modifiers: [.command, .shift])
        .disabled(!store.isConfigured || store.isLoading)
      }
    }
  }
#endif

struct ContentView: View {
  @Environment(Store.self) private var store
  @Environment(\.scenePhase) private var scenePhase
  @State private var selectedItem: Item.ID?
  @State private var showSettings = false
  /// The list and the item open, kept with the window: when iOS closes the
  /// app in the background, it reopens where it was. Swiping it away in the
  /// app switcher discards these, and it starts afresh.
  @SceneStorage("source") private var savedSource = ""
  @SceneStorage("selectedItem") private var savedItem = 0

  #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// The split view's columns are stacked, one screen at a time, so each
    /// screen gets Back (and Home) in its bottom toolbar. Clearing a column's
    /// selection pops back to it.
    private var stacked: Bool { sizeClass == .compact }
  #else
    /// A Mac window always shows the columns side by side.
    private let stacked = false
  #endif

  /// The article column shows an episode.
  private var episodeOpen: Bool {
    selectedItem.flatMap { store.item($0) }?.isEpisode ?? false
  }

  var body: some View {
    NavigationSplitView {
      FeedListView(showSettings: $showSettings)
        .environment(\.showsMiniPlayer, stacked)
    } content: {
      ItemListView(selection: $selectedItem)
        .environment(\.navigation, stacked ? Navigation(back: { store.source = nil }) : nil)
        // Side by side, it moves here from the article column while an
        // episode is open there.
        .environment(\.showsMiniPlayer, stacked || episodeOpen)
    } detail: {
      if let id = selectedItem, let item = store.item(id) {
        ArticleView(item: item)
          .environment(
            \.navigation,
            stacked
              ? Navigation(
                back: { selectedItem = nil },
                home: {
                  selectedItem = nil
                  store.source = nil
                }) : nil
          )
          // An episode's bottom bar has Play, so the mini player stays off
          // its page.
          .environment(\.showsMiniPlayer, !item.isEpisode)
      } else {
        ContentUnavailableView("No item selected", systemImage: "doc.text")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .themedScreen()
          #if os(iOS)
            .miniPlayerAbove()
          #endif
      }
    }
    #if os(macOS)
      // The episode playing, along the bottom of the window. On iPhone and
      // iPad each screen has it above its bottom toolbar instead (see
      // `bottomControls`).
      .safeAreaInset(edge: .bottom, spacing: 0) {
        MiniPlayer()
      }
    #endif
    .settings(isPresented: $showSettings)
    .sensoryFeedback(trigger: store.feedback) { _, new in new?.sensory }
    // pressbox://item/123, from the widgets.
    .onOpenURL { url in
      guard let id = WidgetStore.itemID(in: url) else { return }
      Task {
        await store.reveal(id)
        selectedItem = id
      }
    }
    .overlay {
      if store.isLocked {
        LockView()
      }
    }
    .onChange(of: store.source) { _, source in
      // In an array: JSONDecoder may not take a bare `null`.
      if let data = try? JSONEncoder().encode([source]) {
        savedSource = String(decoding: data, as: UTF8.self)
      }
    }
    .onChange(of: selectedItem) { _, id in savedItem = id.map(Int.init) ?? 0 }
    .task {
      if store.isLocked { await store.unlock() }
      if store.isConfigured {
        await restoreState()
        await store.reload()
      } else {
        showSettings = true
      }
    }
    .onChange(of: scenePhase) { _, phase in
      switch phase {
      case .active:
        Task {
          if store.isLocked { await store.unlock() }
          if store.isConfigured { await store.reload() }
        }
      case .background:
        store.dismissUndoForBackground()
        store.lockIfEnabled()
        Store.scheduleBackgroundRefresh()
      default:
        break
      }
    }
    #if os(macOS)
      // No background refresh on Mac: reload now and then while it's open,
      // which also keeps the Dock badge current.
      .task {
        while !Task.isCancelled {
          try? await Task.sleep(for: .seconds(15 * 60))
          if store.isConfigured && !store.isLocked { await store.reload() }
        }
      }
    #endif
  }
}

extension ContentView {
  /// Back to the list and item the window had open.
  fileprivate func restoreState() async {
    if let saved = try? JSONDecoder().decode([Source?].self, from: Data(savedSource.utf8)),
      let source = saved.first
    {
      store.source = source
    }
    guard selectedItem == nil, savedItem != 0 else { return }
    let id = Int64(savedItem)
    // From the offline cache, or the server.
    await store.reveal(id)
    if store.item(id) != nil { selectedItem = id }
  }
}

extension View {
  /// Settings: a sheet on iPhone and iPad, the Settings window (⌘,) on Mac.
  fileprivate func settings(isPresented: Binding<Bool>) -> some View {
    modifier(SettingsPresentation(isPresented: isPresented))
  }
}

private struct SettingsPresentation: ViewModifier {
  @Binding var isPresented: Bool
  #if os(macOS)
    @Environment(\.openSettings) private var openSettings
  #endif

  func body(content: Content) -> some View {
    #if os(macOS)
      content.onChange(of: isPresented) { _, show in
        guard show else { return }
        isPresented = false
        openSettings()
      }
    #else
      content.sheet(isPresented: $isPresented) {
        SettingsView()
      }
    #endif
  }
}

/// Covers the app while it is locked, including in the app switcher.
struct LockView: View {
  @Environment(Store.self) private var store

  var body: some View {
    ZStack {
      Rectangle().fill(.regularMaterial).ignoresSafeArea()
      VStack(spacing: 16) {
        Image(systemName: "lock.fill").font(.largeTitle)
        Text("pressbox is locked").font(.headline)
        Button("Unlock") { Task { await store.unlock() } }
          .buttonStyle(.glassProminent)
      }
    }
  }
}
