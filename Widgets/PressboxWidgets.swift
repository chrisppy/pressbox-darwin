// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import AppIntents
import SwiftUI
import WidgetKit

/// The widgets: unread items, and the episode playing with Up Next. They
/// draw what the app last wrote (see `WidgetStore`); the app has them redraw
/// when that changes. On iPhone and iPad, also a Control Center control.
@main
struct PressboxWidgets: WidgetBundle {
  var body: some Widget {
    UnreadWidget()
    UpNextWidget()
    #if os(iOS)
      PlaybackControl()
    #endif
  }
}

#if os(iOS)
  /// Play or pause in Control Center (and on the Lock Screen, or the Action
  /// button): what plays, or the first in Up Next.
  struct PlaybackControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
      StaticControlConfiguration(kind: "org.red-oxide.pressbox.playback") {
        ControlWidgetButton(action: TogglePlaybackIntent()) {
          Label("Play or Pause", systemImage: "playpause.fill")
        }
      }
      .displayName("pressbox")
      .description("Plays or pauses the episode, or plays the first in Up Next.")
    }
  }
#endif

struct SnapshotEntry: TimelineEntry {
  let date: Date
  let snapshot: WidgetSnapshot
}

/// One entry, from the snapshot: the app reloads the widgets when it changes,
/// so there is nothing to schedule.
struct SnapshotProvider: TimelineProvider {
  func placeholder(in context: Context) -> SnapshotEntry {
    SnapshotEntry(date: .now, snapshot: .preview)
  }

  func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
    let snapshot = WidgetStore.load()
    completion(
      SnapshotEntry(
        date: .now, snapshot: context.isPreview && !snapshot.configured ? .preview : snapshot))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
    completion(
      Timeline(entries: [SnapshotEntry(date: .now, snapshot: WidgetStore.load())], policy: .never))
  }
}

// MARK: Unread

struct UnreadWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: WidgetStore.unreadKind, provider: SnapshotProvider()) { entry in
      UnreadView(snapshot: entry.snapshot)
        .containerBackground(Color("Background"), for: .widget)
    }
    .configurationDisplayName("Unread")
    .description("How many items are unread, and the newest of them.")
    .supportedFamilies(Self.families)
  }

  #if os(iOS)
    static let families: [WidgetFamily] = [
      .systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular,
    ]
  #else
    static let families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge]
  #endif
}

struct UnreadView: View {
  @Environment(\.widgetFamily) private var family
  let snapshot: WidgetSnapshot

  var body: some View {
    if !snapshot.configured {
      NotSetUp()
    } else if isAccessory {
      accessory
    } else if family == .systemSmall {
      small
    } else {
      list(rows: family == .systemLarge ? 7 : 3)
    }
  }

  /// On the Lock Screen (iPhone and iPad).
  private var isAccessory: Bool {
    #if os(iOS)
      family == .accessoryCircular || family == .accessoryRectangular
    #else
      false
    #endif
  }

  @ViewBuilder private var accessory: some View {
    #if os(iOS)
      if family == .accessoryCircular {
        VStack(spacing: 0) {
          Text(snapshot.unread, format: .number).font(.title2.weight(.semibold))
          Text("unread").font(.caption2)
        }
        .widgetAccentable()
      } else {
        VStack(alignment: .leading) {
          Text("\(snapshot.unread) unread").font(.headline).widgetAccentable()
          if let first = snapshot.latest.first {
            Text(first.title).font(.caption).lineLimit(2)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    #endif
  }

  private var small: some View {
    VStack(alignment: .leading, spacing: 4) {
      Label("pressbox", systemImage: "tray.full").font(.caption).foregroundStyle(.tint)
      Spacer()
      Text(snapshot.unread, format: .number)
        .font(.system(size: 44, weight: .semibold, design: .rounded))
        .minimumScaleFactor(0.5)
      Text(snapshot.unread == 1 ? "unread item" : "unread items")
        .font(.caption)
        .foregroundStyle(Color("MutedText"))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .foregroundStyle(Color("Text"))
  }

  private func list(rows: Int) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Label("Unread", systemImage: "tray.full").foregroundStyle(.tint)
        Spacer()
        Text(snapshot.unread, format: .number).foregroundStyle(Color("MutedText"))
      }
      .font(.caption.weight(.semibold))
      if snapshot.latest.isEmpty {
        Spacer()
        Text("All Caught Up").font(.headline).frame(maxWidth: .infinity)
        Spacer()
      } else {
        ForEach(snapshot.latest.prefix(rows)) { entry in
          Link(destination: WidgetStore.link(entry.id)) { EntryRow(entry: entry) }
        }
        Spacer(minLength: 0)
      }
    }
    .foregroundStyle(Color("Text"))
  }
}

// MARK: Up Next

struct UpNextWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: WidgetStore.upNextKind, provider: SnapshotProvider()) { entry in
      UpNextView(snapshot: entry.snapshot)
        .containerBackground(Color("Background"), for: .widget)
    }
    .configurationDisplayName("Up Next")
    .description("The episode playing, with play and pause, and what plays after it.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

struct UpNextView: View {
  @Environment(\.widgetFamily) private var family
  let snapshot: WidgetSnapshot

  /// The episode the button plays: the one playing, or the first in Up Next.
  private var current: WidgetSnapshot.Entry? { snapshot.nowPlaying ?? snapshot.upNext.first }

  /// What follows `current`.
  private var after: [WidgetSnapshot.Entry] {
    Array(snapshot.upNext.filter { $0.id != current?.id }.prefix(3))
  }

  var body: some View {
    if !snapshot.configured {
      NotSetUp()
    } else if let current {
      HStack(alignment: .top, spacing: 12) {
        nowPlaying(current)
        if family == .systemMedium {
          VStack(alignment: .leading, spacing: 6) {
            Text("Up Next").font(.caption.weight(.semibold)).foregroundStyle(.tint)
            if after.isEmpty {
              Text("Nothing after this").font(.caption).foregroundStyle(Color("MutedText"))
            }
            ForEach(after) { entry in
              Link(destination: WidgetStore.link(entry.id)) { EntryRow(entry: entry) }
            }
            Spacer(minLength: 0)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .foregroundStyle(Color("Text"))
    } else {
      VStack(spacing: 6) {
        Image(systemName: "text.line.first.and.arrowtriangle.forward")
          .font(.title2)
          .foregroundStyle(.tint)
        Text(snapshot.hasQueue ? "Up Next is empty" : "Nothing playing")
          .font(.headline)
        if snapshot.hasQueue {
          Text("Touch and hold an episode to add it.")
            .font(.caption)
            .foregroundStyle(Color("MutedText"))
            .multilineTextAlignment(.center)
        }
      }
      .foregroundStyle(Color("Text"))
    }
  }

  private func nowPlaying(_ entry: WidgetSnapshot.Entry) -> some View {
    let playing = snapshot.isPlaying && snapshot.nowPlaying?.id == entry.id
    return VStack(alignment: .leading, spacing: 6) {
      Link(destination: WidgetStore.link(entry.id)) {
        VStack(alignment: .leading, spacing: 2) {
          Text(entry.feed).font(.caption).foregroundStyle(Color("MutedText")).lineLimit(1)
          Text(entry.title).font(.subheadline.weight(.semibold)).lineLimit(3)
        }
      }
      Spacer(minLength: 0)
      if snapshot.nowPlaying?.id == entry.id { progress(playing: playing) }
      Button(intent: TogglePlaybackIntent()) {
        Label(playing ? "Pause" : "Play", systemImage: playing ? "pause.fill" : "play.fill")
          .labelStyle(.iconOnly)
          .font(.title3)
          .frame(width: 44, height: 44)
          .background(Circle().fill(.tint))
          .foregroundStyle(Color("Background"))
      }
      .buttonStyle(.plain)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// While playing, the bar moves on its own, from where playback was when
  /// the app last wrote.
  @ViewBuilder private func progress(playing: Bool) -> some View {
    if let duration = snapshot.duration, duration > 0 {
      if playing {
        let rate = Double(max(snapshot.rate, 0.1))
        let start = snapshot.written.addingTimeInterval(-snapshot.position / rate)
        let end = start.addingTimeInterval(duration / rate)
        if end > start {
          ProgressView(timerInterval: start...end, countsDown: false) {
            EmptyView()
          } currentValueLabel: {
            EmptyView()
          }
        }
      } else {
        ProgressView(value: min(snapshot.position, duration), total: duration)
      }
    }
  }
}

// MARK: Shared pieces

struct EntryRow: View {
  let entry: WidgetSnapshot.Entry

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(entry.title).font(.caption.weight(.semibold)).lineLimit(1)
      Text(entry.feed).font(.caption2).foregroundStyle(Color("MutedText")).lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct NotSetUp: View {
  var body: some View {
    VStack(spacing: 6) {
      Image(systemName: "tray.full").font(.title2).foregroundStyle(.tint)
      Text("Open pressbox to connect to your server.")
        .font(.caption)
        .multilineTextAlignment(.center)
        .foregroundStyle(Color("Text"))
    }
  }
}

extension WidgetSnapshot {
  /// For the widget gallery.
  static var preview: WidgetSnapshot {
    let entry = { (id: Int64, title: String, feed: String) in
      WidgetSnapshot.Entry(id: id, title: title, feed: feed, published: 0)
    }
    var snapshot = WidgetSnapshot()
    snapshot.configured = true
    snapshot.unread = 12
    snapshot.latest = [
      entry(1, "A new release, and what changed", "Project news"),
      entry(2, "Notes from the weekend", "A blog"),
      entry(3, "The week in review", "Weekly digest"),
    ]
    snapshot.nowPlaying = entry(4, "Episode 42: Up Next", "A podcast")
    snapshot.position = 600
    snapshot.duration = 1800
    snapshot.hasQueue = true
    snapshot.upNext = [entry(5, "Episode 43", "A podcast"), entry(6, "Interview", "Another show")]
    snapshot.written = .now
    return snapshot
  }
}
