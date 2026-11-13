// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import SwiftUI

/// News and Podcasts, for the bottom bars of the feed list, All items and
/// Starred: both on shows everything. Turning off the only one on switches
/// to the other, so the lists are never empty by choice. A function rather
/// than a view, so the toolbar gets them as two buttons, not one.
@MainActor @ViewBuilder
func kindToggles(_ store: Store) -> some View {
  Toggle(isOn: kindBinding(store, \.news, update: { $0.set(news: $1) })) {
    Label("News", systemImage: "newspaper")
  }
  .toggleStyle(.button)
  Toggle(isOn: kindBinding(store, \.podcasts, update: { $0.set(podcasts: $1) })) {
    Label("Podcasts", systemImage: "headphones")
  }
  .toggleStyle(.button)
}

@MainActor
private func kindBinding(
  _ store: Store, _ kind: KeyPath<Shows, Bool>, update: @escaping (inout Shows, Bool) -> Void
) -> Binding<Bool> {
  Binding(
    get: { store.shows[keyPath: kind] },
    set: { value in
      var shows = store.shows
      update(&shows, value)
      store.haptic(.toggle)
      Task { await store.setShows(shows) }
    })
}
