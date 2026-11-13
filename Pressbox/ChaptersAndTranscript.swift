// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import SwiftUI

/// An episode's chapters; while it plays, the current one is marked and a
/// tap jumps to one.
struct ChapterList: View {
  @Environment(Store.self) private var store
  let item: Item
  let chapters: [Chapter]

  var body: some View {
    let playback = store.playback
    let playing = playback.isCurrent(item)
    let current = playing ? playback.chapter : nil
    List(chapters.filter { !$0.isHidden }) { chapter in
      Button {
        if playing { playback.seek(to: chapter.start) }
      } label: {
        HStack {
          Text(formatTime(chapter.start))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(minWidth: 56, alignment: .leading)
          Text(chapter.title ?? "")
            .fontWeight(current == chapter ? .semibold : .regular)
          Spacer()
          if current == chapter {
            Image(systemName: "speaker.wave.2.fill").foregroundStyle(Color.accentColor)
          }
        }
      }
      .disabled(!playing)
      .foregroundStyle(.primary)
    }
    .overlay {
      if chapters.isEmpty {
        ContentUnavailableView("No chapters yet", systemImage: "list.bullet")
      }
    }
  }
}

/// An episode's transcript; while it plays, the line being heard is
/// highlighted and followed, and a tap jumps to a line.
struct TranscriptView: View {
  @Environment(Store.self) private var store
  let item: Item
  @State private var transcript: Transcript?
  @State private var loaded = false

  var body: some View {
    let playback = store.playback
    let playing = playback.isCurrent(item)
    let now = playing ? playback.position : nil
    let current = now.flatMap { at in transcript?.segments.last { $0.start <= at && at < $0.end } }
    ScrollViewReader { proxy in
      List(transcript?.segments ?? []) { segment in
        Button {
          if playing { playback.seek(to: segment.start) }
        } label: {
          VStack(alignment: .leading, spacing: 2) {
            HStack {
              Text(formatTime(segment.start)).monospacedDigit()
              if let speaker = segment.speaker {
                Text(speaker).fontWeight(.semibold)
              }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(segment.text)
              .foregroundStyle(segment == current ? Color.accentColor : .primary)
          }
        }
        .disabled(!playing)
        .id(segment.id)
      }
      .listStyle(.plain)
      .onChange(of: current) { _, segment in
        if let segment { withAnimation { proxy.scrollTo(segment.id, anchor: .center) } }
      }
    }
    .overlay {
      if !loaded {
        ProgressView()
      } else if transcript == nil {
        ContentUnavailableView("No transcript", systemImage: "text.quote")
      }
    }
    .navigationTitle("Transcript")
    .inlineTitle()
    .task {
      transcript = await store.transcript(for: item)
      loaded = true
    }
  }
}
