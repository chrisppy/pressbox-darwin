// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import SwiftUI

/// The episodes to play next, in order: tap one to play it, drag to
/// reorder, swipe (or Delete on Mac) to remove. When an episode ends, the
/// first one here starts.
struct UpNextView: View {
  @Environment(Store.self) private var store
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        ForEach(store.queue) { item in
          Button {
            Task { await store.playback.play(item) }
          } label: {
            ItemRow(item: item, feedTitle: store.feedTitle(item.feedId))
          }
          .foregroundStyle(.primary)
          .contextMenu {
            Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
              Task { await store.enqueue(item, next: true) }
            }
            Button("Remove from Up Next", systemImage: "minus.circle", role: .destructive) {
              Task { await store.dequeue(item) }
            }
          }
        }
        .onMove { from, to in
          var queue = store.queue
          queue.move(fromOffsets: from, toOffset: to)
          Task { await store.setQueue(queue) }
        }
        .onDelete { offsets in
          var queue = store.queue
          queue.remove(atOffsets: offsets)
          Task { await store.setQueue(queue) }
        }
      }
      .listStyle(.plain)
      .themedSheet()
      .overlay {
        if store.queue.isEmpty {
          ContentUnavailableView(
            "Up Next is empty", systemImage: NowPlayingView.upNextSymbol,
            description: Text(
              "Touch and hold an episode in a list, or use Add to Up Next in its bottom bar, to queue it."
            ))
        }
      }
      .navigationTitle("Up Next")
      .inlineTitle()
      .toolbar {
        #if os(iOS)
          ToolbarItem(placement: .cancellationAction) {
            EditButton().disabled(store.queue.isEmpty)
          }
        #endif
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
    .presentationDetents([.medium, .large])
    .macSheetSize(width: 420, height: 480)
  }
}
