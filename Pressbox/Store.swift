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
  // What the Store+ files use is internal, not private (Swift's private ends
  // at the file); only the store and its extensions set these.

  /// Full articles opened or prefetched, for offline reading.
  var articles: [Int64: Item] = [:]
  /// Read, starred and position changes the server hasn't had yet.
  private(set) var outbox = Outbox()
  private var isFlushing = false
  /// The episodes to play next, in order, as the server keeps them.
  var queue: [Item] = []
  /// The server keeps a queue (older ones don't), so Up Next is shown.
  var hasQueue = false
  /// The newest unread items in any feed, for the widgets.
  var latestUnread: [Item] = []
  var widgetUpdate: Task<Void, Never>?

  // Pairing in progress: the code to show the user.
  var pairCode: String?
  var pairStatus: String?
  var pairTask: Task<Void, Never>?

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
    // Playback from the widget, Control Center, Siri and Shortcuts.
    PlaybackBridge.toggle = { [weak self] in await self?.togglePlayback() }
    PlaybackBridge.skip = { [weak self] by in self?.playback.skip(by) }
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

  /// Unread items in a list; Mark all as read marks these.
  func unread(in source: Source) -> Int {
    switch source {
    case .all: totalUnread
    case .feed(let id): feeds.first { $0.id == id }?.unread ?? 0
    case .tag(let tag): unread(tagged: tag)
    default: 0
    }
  }

  var api: APIClient { APIClient(server: server, token: token) }

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
  func run(_ body: () async throws -> Void) async {
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
  func send(_ change: Change) async -> Bool {
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

  func saveCache() {
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
}
