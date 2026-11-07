// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import SwiftUI

@main
struct PressboxApp: App {
  @State private var store = Store()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environment(store)
    }
    .backgroundTask(.appRefresh(Store.refreshTaskID)) {
      await Store.backgroundRefresh()
    }
  }
}

struct ContentView: View {
  @Environment(Store.self) private var store
  @Environment(\.scenePhase) private var scenePhase
  @State private var selectedItem: Item.ID?
  @State private var showSettings = false

  var body: some View {
    NavigationSplitView {
      FeedListView(showSettings: $showSettings)
    } content: {
      ItemListView(selection: $selectedItem)
    } detail: {
      if let id = selectedItem, let item = store.item(id) {
        ArticleView(item: item)
      } else {
        ContentUnavailableView("No item selected", systemImage: "doc.text")
      }
    }
    .sheet(isPresented: $showSettings) {
      SettingsView()
    }
    .overlay {
      if store.isLocked {
        LockView()
      }
    }
    .task {
      if store.isLocked { await store.unlock() }
      if store.isConfigured {
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
        store.lockIfEnabled()
        Store.scheduleBackgroundRefresh()
      default:
        break
      }
    }
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
          .buttonStyle(.borderedProminent)
      }
    }
  }
}
