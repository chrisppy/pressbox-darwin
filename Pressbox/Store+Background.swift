// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import Foundation
import UserNotifications
#if os(iOS)
  import BackgroundTasks
#endif

/// The unread badge, and background refresh (badge, widgets, downloads).
extension Store {
  func setBadgeEnabled(_ enabled: Bool) async {
    if enabled {
      let granted =
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.badge]))
        ?? false
      badgeEnabled = granted
      if !granted { errorMessage = Self.allowBadgesMessage }
    } else {
      badgeEnabled = false
    }
    updateBadge()
    Self.scheduleBackgroundRefresh()
  }

  func updateBadge() {
    let count = badgeEnabled ? totalUnread : 0
    UNUserNotificationCenter.current().setBadgeCount(count)
    updateWidgets()
  }

  #if os(macOS)
    private static let allowBadgesMessage =
      "Allow badges for pressbox in System Settings › Notifications."
  #else
    private static let allowBadgesMessage = "Allow badges for pressbox in the Settings app."
  #endif

  /// Asks iOS to wake the app in a while to update the badge. iOS decides
  /// when, based on how often the app is used. The Mac app has no background
  /// refresh; it reloads on a timer while open instead (see `ContentView`).
  nonisolated static func scheduleBackgroundRefresh() {
    #if os(iOS)
      // For the badge and the widgets.
      guard !(UserDefaults.standard.string(forKey: "server") ?? "").isEmpty else {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshTaskID)
        return
      }
      let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
      request.earliestBeginDate = Date().addingTimeInterval(30 * 60)
      try? BGTaskScheduler.shared.submit(request)
    #endif
  }

  /// The background refresh: fetch unread counts and set the badge.
  nonisolated static func backgroundRefresh() async {
    scheduleBackgroundRefresh()
    let defaults = UserDefaults.standard
    guard let server = defaults.string(forKey: "server"),
      let token = Keychain.token()
    else { return }
    let api = APIClient(server: server, token: token)
    guard let feeds = try? await api.feeds() else { return }
    let unread = feeds.filter { !$0.isArchived }.reduce(0) { $0 + $1.unread }
    if defaults.bool(forKey: "badgeEnabled") {
      try? await UNUserNotificationCenter.current().setBadgeCount(unread)
    }
    // The widgets: new counts and items; what plays is as the app left it.
    var snapshot = WidgetStore.load()
    snapshot.configured = true
    snapshot.unread = unread
    // New episodes, downloaded while the app is away.
    if let episodes = try? await api.unreadEpisodes(limit: 50) {
      await Downloads.shared.sync(unread: episodes, api: api)
    }
    if let latest = try? await api.items(source: .all, unreadOnly: true, limit: 8).items {
      let titles = Dictionary(feeds.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
      snapshot.latest = latest.map {
        WidgetSnapshot.Entry(
          id: $0.id, title: $0.title, feed: titles[$0.feedId] ?? $0.feedId,
          published: $0.published)
      }
    }
    WidgetStore.save(snapshot)
  }
}
