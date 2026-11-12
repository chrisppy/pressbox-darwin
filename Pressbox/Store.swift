// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import Foundation
import LocalAuthentication
import Observation
import UserNotifications

#if os(iOS)
  import BackgroundTasks
  import UIKit
#endif

/// App state shared by every view.
@MainActor
@Observable
final class Store {
  nonisolated static let refreshTaskID = "org.red-oxide.pressbox.refresh"

  var feeds: [Feed] = []
  var items: [Item] = []
  var source: Source? = .all
  var unreadOnly = true
  /// Active full-text search; searches include read items.
  var search: String?
  /// Where the next page of `items` starts, if there is one.
  var nextPage: NextPage?
  var isLoading = false
  var errorMessage: String?
  /// The last load failed for lack of a connection; showing cached data.
  var isOffline = false
  /// Full articles opened or prefetched, for offline reading.
  private(set) var articles: [Int64: Item] = [:]
  /// Read, starred and position changes the server hasn't had yet.
  private(set) var outbox = Outbox()
  private var isFlushing = false
  /// The episodes to play next, in order, as the server keeps them.
  private(set) var queue: [Item] = []
  /// The server keeps a queue (older ones don't), so Up Next is shown.
  private(set) var hasQueue = false
  /// The newest unread items in any feed, for the widgets.
  private var latestUnread: [Item] = []
  private var widgetUpdate: Task<Void, Never>?

  // Pairing in progress: the code to show the user.
  var pairCode: String?
  var pairStatus: String?
  private var pairTask: Task<Void, Never>?

  /// Plays podcast episodes.
  let playback = Playback()

  var isLocked = false
  /// Who this device is signed in as.
  var me: Me?
  var serverVersion: ServerVersion?

  var server: String {
    didSet { UserDefaults.standard.set(server, forKey: "server") }
  }
  var token: String {
    didSet { Keychain.setToken(token) }
  }
  var lockEnabled: Bool {
    didSet { UserDefaults.standard.set(lockEnabled, forKey: "lockEnabled") }
  }
  var badgeEnabled: Bool {
    didSet { UserDefaults.standard.set(badgeEnabled, forKey: "badgeEnabled") }
  }
  /// Mark items read as they scroll off the top of the list.
  var markReadOnScroll: Bool {
    didSet { UserDefaults.standard.set(markReadOnScroll, forKey: "markReadOnScroll") }
  }

  init() {
    server = UserDefaults.standard.string(forKey: "server") ?? ""
    token = Keychain.token() ?? ""
    lockEnabled = UserDefaults.standard.bool(forKey: "lockEnabled")
    badgeEnabled = UserDefaults.standard.bool(forKey: "badgeEnabled")
    markReadOnScroll = UserDefaults.standard.bool(forKey: "markReadOnScroll")
    isLocked = lockEnabled
    if let snapshot = Cache.load() {
      feeds = snapshot.feeds
      items = snapshot.items
      articles = snapshot.articles
      queue = snapshot.queue ?? []
      hasQueue = snapshot.queue != nil
    }
    outbox = Cache.loadOutbox()
    playback.store = self
    // The Up Next widget's play/pause button.
    PlaybackBridge.toggle = { [weak self] in await self?.togglePlayback() }
  }

  var isConfigured: Bool {
    !server.trimmingCharacters(in: .whitespaces).isEmpty && !token.isEmpty
  }
  var totalUnread: Int { feeds.filter { !$0.isArchived }.reduce(0) { $0 + $1.unread } }

  /// Tags of the feeds in the server's config, sorted.
  var tags: [String] {
    Set(feeds.filter { !$0.isArchived }.flatMap(\.tags)).sorted()
  }

  /// Feeds in the server's config with this tag.
  func feedsTagged(_ tag: String) -> [Feed] {
    feeds.filter { !$0.isArchived && $0.tags.contains(tag) }
  }

  func unread(tagged tag: String) -> Int {
    feedsTagged(tag).reduce(0) { $0 + $1.unread }
  }

  private var api: APIClient { APIClient(server: server, token: token) }

  func title(for source: Source) -> String {
    switch source {
    case .all: "All items"
    case .starred: "Starred"
    case .feed(let id): feedTitle(id)
    case .tag(let tag): tag
    }
  }

  func feedTitle(_ id: String) -> String {
    feeds.first { $0.id == id }?.title ?? id
  }

  func item(_ id: Int64) -> Item? {
    items.first { $0.id == id } ?? articles[id] ?? queue.first { $0.id == id }
  }

  /// Runs a request, showing any error instead of throwing it.
  private func run(_ body: () async throws -> Void) async {
    do {
      try await body()
      errorMessage = nil
      isOffline = false
    } catch is CancellationError {
    } catch let error as URLError where error.code == .cancelled {
    } catch  where Self.isConnectionError(error) {
      isOffline = true
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  /// The server couldn't be reached: worth trying again later.
  private static func isConnectionError(_ error: Error) -> Bool {
    guard let error = error as? URLError else { return false }
    return [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost]
      .contains(error.code)
  }

  /// Sends a change to the server, or keeps it in the outbox to send later
  /// if the server can't be reached (or the request was cancelled). Returns
  /// false only if the server refused it.
  private func send(_ change: Change) async -> Bool {
    let before = outbox
    defer { if outbox != before { Cache.saveOutbox(outbox) } }
    // While the outbox is being sent, queue behind it, so an older change to
    // the same item can't reach the server after this one.
    if isFlushing {
      outbox.add(change)
      return true
    }
    outbox.supersede(with: change)
    do {
      try await api.submit(change)
      errorMessage = nil
      isOffline = false
    } catch  where Self.isConnectionError(error) || Self.isCancellation(error) {
      isOffline = isOffline || Self.isConnectionError(error)
      outbox.add(change)
    } catch {
      errorMessage = error.localizedDescription
      return false
    }
    return true
  }

  private static func isCancellation(_ error: Error) -> Bool {
    error is CancellationError || (error as? URLError)?.code == .cancelled
  }

  /// Sends the changes kept while offline, before anything is loaded so the
  /// server's unread counts include them. Stops if the server still can't be
  /// reached. A change the server refuses (an item it no longer has, say) is
  /// dropped, since sending it again won't help.
  private func flushOutbox() async {
    guard !outbox.isEmpty, !isFlushing else { return }
    isFlushing = true
    defer {
      isFlushing = false
      Cache.saveOutbox(outbox)
    }
    // One at a time, taking the next from the outbox each round, so changes
    // made meanwhile are sent too.
    while let change = outbox.changes.first {
      do {
        try await api.submit(change)
      } catch  where Self.isConnectionError(error) || Self.isCancellation(error) {
        return
      } catch {
        // Refused: drop it.
      }
      outbox.remove(change)
    }
  }

  private func saveCache() {
    Cache.save(
      Snapshot(feeds: feeds, items: items, articles: articles, queue: hasQueue ? queue : nil))
  }

  func reload() async {
    guard isConfigured else {
      errorMessage = APIError.notConfigured.errorDescription
      return
    }
    isLoading = true
    defer { isLoading = false }
    await flushOutbox()
    await run {
      feeds = try await api.feeds()
      try await loadItems()
      try await loadQueue()
      latestUnread = try await api.items(source: .all, unreadOnly: true, limit: 8).items
      if me == nil { me = try await api.me() }
      // Older servers don't have the endpoint; that's not an error.
      if serverVersion == nil { serverVersion = try? await api.version() }
    }
    updateBadge()
    saveCache()
    updateWidgets()
    await syncDownloads()
    await prefetchUnread()
  }

  /// Downloads the newest unread episodes, and removes downloads done with.
  private func syncDownloads() async {
    guard let unread = try? await api.unreadEpisodes(limit: 50) else { return }
    await Downloads.shared.sync(unread: unread, api: api)
  }

  /// Deletes an episode's download, unless it is the one playing.
  private func dropDownload(_ id: Int64) {
    guard playback.item?.id != id else { return }
    Downloads.shared.remove(id)
  }

  func loadItems() async throws {
    guard let source else { return }
    let page = try await api.items(source: source, unreadOnly: unreadOnly, search: search)
    items = page.items
    nextPage = page.next
  }

  func select(_ source: Source?) async {
    self.source = source
    items = []
    await run { try await loadItems() }
  }

  func setUnreadOnly(_ value: Bool) async {
    unreadOnly = value
    await run { try await loadItems() }
  }

  func setSearch(_ text: String?) async {
    let text = text?.trimmingCharacters(in: .whitespaces)
    search = (text?.isEmpty ?? true) ? nil : text
    await run { try await loadItems() }
  }

  func loadMoreIfNeeded(after item: Item) async {
    guard let next = nextPage, let source,
      items.suffix(5).contains(where: { $0.id == item.id })
    else { return }
    nextPage = nil
    await run {
      let page = try await api.items(
        source: source, unreadOnly: unreadOnly, search: search, after: next)
      items.append(contentsOf: page.items)
      nextPage = page.next
    }
  }

  /// The full item with content, from the server or the offline cache, and
  /// marks it read, unless it is a podcast episode: those are read once
  /// played to the end.
  func open(_ item: Item) async -> Item {
    var full = articles[item.id] ?? item
    await run {
      full = try await api.item(item.id)
      articles[item.id] = full
    }
    if !full.isEpisode {
      await setRead(full, true)
      full.read = true
    }
    saveCache()
    return full
  }

  // MARK: Podcasts

  /// An episode's chapters; none if it has none or they can't be had.
  func chapters(for item: Item) async -> [Chapter] {
    (try? await api.chapters(item.id)) ?? []
  }

  /// An episode's transcript, or `nil`.
  func transcript(for item: Item) async -> Transcript? {
    var transcript: Transcript?
    await run { transcript = try await api.transcript(item.id) }
    return transcript
  }

  /// Saves where playback stopped, here and on the server.
  func savePosition(_ item: Item, _ position: Int) async {
    update(item.id) { $0.position = position }
    _ = await send(.position(item.id, position))
  }

  /// An episode played to the end: read, its position forgotten, and out of
  /// Up Next.
  func finished(_ item: Item) async {
    await savePosition(item, 0)
    let current = self.item(item.id) ?? articles[item.id] ?? item
    await setRead(current, true)
    // Already read (played again), marking it read changed nothing.
    if isQueued(item) { await dequeue(item) }
    dropDownload(item.id)
  }

  // MARK: Up Next

  private func loadQueue() async throws {
    do {
      queue = try await api.queue()
      hasQueue = true
    } catch APIError.notFound {
      // An older server, without a queue.
      queue = []
      hasQueue = false
    }
  }

  func isQueued(_ item: Item) -> Bool { queue.contains { $0.id == item.id } }

  /// Adds an episode to Up Next: to play next, or after the rest. Moves it
  /// there if it is queued already.
  func enqueue(_ item: Item, next: Bool = false) async {
    var new = queue.filter { $0.id != item.id }
    if next { new.insert(item, at: 0) } else { new.append(item) }
    await setQueue(new)
  }

  func dequeue(_ item: Item) async {
    await setQueue(queue.filter { $0.id != item.id })
  }

  /// Replaces Up Next (to reorder it, say): here at once, and on the server
  /// as soon as it can be reached.
  func setQueue(_ new: [Item]) async {
    let old = queue
    queue = new
    saveCache()
    updateWidgets()
    if !(await send(.queue(new.map(\.id)))) {
      queue = old
      saveCache()
    }
  }

  /// Downloads the content of unread items not cached yet, so they can be
  /// read offline.
  private func prefetchUnread() async {
    let missing = items.filter { !$0.read && articles[$0.id] == nil }.prefix(30)
    guard !missing.isEmpty else { return }
    for item in missing {
      guard let full = try? await api.item(item.id) else { break }
      articles[item.id] = full
    }
    saveCache()
  }

  /// Marks an item read or unread: here at once, and on the server as soon as
  /// it can be reached. Undone if the server refuses it.
  func setRead(_ item: Item, _ value: Bool) async {
    guard item.read != value else { return }
    applyRead(item, value)
    if !(await send(.read(item.id, value))) { applyRead(item, !value) }
  }

  private func applyRead(_ item: Item, _ value: Bool) {
    update(item.id) { $0.read = value }
    // As on the server: read items leave Up Next.
    if value {
      queue.removeAll { $0.id == item.id }
      latestUnread.removeAll { $0.id == item.id }
      dropDownload(item.id)
    }
    if let i = feeds.firstIndex(where: { $0.id == item.feedId }) {
      feeds[i].unread = max(0, feeds[i].unread + (value ? -1 : 1))
    }
    updateBadge()
    saveCache()
  }

  /// Stars or unstars an item, as `setRead` does.
  func setStarred(_ item: Item, _ value: Bool) async {
    update(item.id) { $0.starred = value }
    saveCache()
    if !(await send(.starred(item.id, value))) {
      update(item.id) { $0.starred = !value }
      saveCache()
    }
  }

  func markAllRead() async {
    let targets: [String]
    switch source {
    case .feed(let id): targets = [id]
    case .tag(let tag): targets = feedsTagged(tag).filter { $0.unread > 0 }.map(\.id)
    case .all: targets = feeds.filter { $0.unread > 0 }.map(\.id)
    default: return
    }
    await run {
      for id in targets { _ = try await api.markFeedRead(id) }
    }
    await reload()
  }

  func refreshServer() async {
    await run { try await api.refresh() }
    try? await Task.sleep(for: .seconds(3))
    await reload()
  }

  private func update(_ id: Int64, _ change: (inout Item) -> Void) {
    for i in items.indices where items[i].id == id { change(&items[i]) }
    for i in queue.indices where queue[i].id == id { change(&queue[i]) }
    if articles[id] != nil { change(&articles[id]!) }
  }

  // MARK: Pairing

  /// Asks the server to pair this device and waits for approval.
  func startPairing(server newServer: String, name: String) {
    pairTask?.cancel()
    server = newServer.trimmingCharacters(in: .whitespacesAndNewlines)
    pairCode = nil
    pairStatus = "Contacting the server…"
    let client = APIClient(server: server, token: nil)
    pairTask = Task {
      do {
        let start = try await client.pairStart(name: name)
        pairCode = start.code
        pairStatus = "Waiting for approval…"
        let deadline = Date().addingTimeInterval(TimeInterval(start.expiresIn))
        while Date() < deadline {
          try await Task.sleep(for: .seconds(2))
          if let approved = try await client.pairPoll(start.pollId) {
            token = approved.token
            me = nil
            pairCode = nil
            pairStatus = "Paired as \(approved.name)."
            await reload()
            return
          }
        }
        pairCode = nil
        pairStatus = "The code expired. Try again."
      } catch is CancellationError {
      } catch {
        pairCode = nil
        pairStatus = error.localizedDescription
      }
    }
  }

  func cancelPairing() {
    pairTask?.cancel()
    pairCode = nil
    pairStatus = nil
  }

  /// Approves another device's pairing code, for `user` if given (admins
  /// only). Returns "device for user" on success.
  func approve(code: String, user: String? = nil) async -> String? {
    var result: String?
    await run {
      let approved = try await api.approve(code: code, user: user)
      result = "\(approved.name) for \(approved.user)"
    }
    return result
  }

  // MARK: Widgets

  /// Writes what the widgets show, a moment after the last change (one action
  /// can change several things).
  func updateWidgets() {
    widgetUpdate?.cancel()
    widgetUpdate = Task {
      try? await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled else { return }
      WidgetStore.save(widgetSnapshot())
    }
  }

  private func widgetSnapshot() -> WidgetSnapshot {
    let entry = { (item: Item) in
      WidgetSnapshot.Entry(
        id: item.id, title: item.title, feed: self.feedTitle(item.feedId),
        published: item.published)
    }
    var snapshot = WidgetSnapshot()
    snapshot.configured = isConfigured
    snapshot.unread = totalUnread
    snapshot.latest = latestUnread.filter { !$0.read }.map(entry)
    if let item = playback.item {
      snapshot.nowPlaying = entry(item)
      snapshot.isPlaying = playback.isPlaying
      snapshot.position = playback.position
      snapshot.duration = playback.duration
      snapshot.rate = playback.rate
    }
    snapshot.hasQueue = hasQueue
    snapshot.upNext = queue.filter { $0.id != playback.item?.id }.prefix(4).map(entry)
    snapshot.written = Date()
    return snapshot
  }

  /// The widget's button: pauses or resumes, or plays the first in Up Next.
  func togglePlayback() async {
    if playback.item != nil {
      playback.togglePause()
    } else if let next = queue.first {
      await playback.play(next)
    }
  }

  /// Shows an item a widget opened, fetching it if no list here has it.
  func reveal(_ id: Int64) async {
    if item(id) == nil {
      await run {
        let full = try await api.item(id)
        articles[id] = full
      }
    }
    if source == nil { source = .all }
  }

  func forget() {
    playback.discard()
    token = ""
    me = nil
    feeds = []
    items = []
    articles = [:]
    queue = []
    hasQueue = false
    latestUnread = []
    updateWidgets()
    Downloads.shared.removeAll()
    outbox = Outbox()
    Cache.clear()
  }

  // MARK: Face ID (Touch ID on Mac) lock

  func lockIfEnabled() {
    if lockEnabled { isLocked = true }
  }

  func unlock() async {
    let context = LAContext()
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
      // No passcode set: there is nothing to unlock with.
      isLocked = false
      return
    }
    let ok = try? await context.evaluatePolicy(
      .deviceOwnerAuthentication, localizedReason: "Unlock your feeds")
    isLocked = !(ok ?? false)
  }

  // MARK: Unread badge and background refresh

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

  private func updateBadge() {
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
