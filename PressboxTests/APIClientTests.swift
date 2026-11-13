// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import Foundation
import Testing

@testable import Pressbox

// APIClient against a fake server (StubServer): the requests it builds, and
// what it makes of the answers.

/// The APIError `work` throws, if any.
private func apiError(_ work: () async throws -> Void) async -> APIError? {
  do {
    try await work()
  } catch let error as APIError {
    return error
  } catch {
    Issue.record("not an APIError: \(error)")
  }
  return nil
}

struct APIClientRequestTests {
  @Test func sendsTheTokenAndDecodesSnakeCase() async throws {
    let (api, server) = StubServer.client(
      body: #"""
        [{"id":"news","title":"News","url":"https://x/feed","site_url":"https://x",
          "tags":["daily"],"unread":2,"total":5,"last_fetched":100}]
        """#)
    let feeds = try await api.feeds()
    #expect(feeds.map(\.id) == ["news"])
    #expect(feeds.first?.siteUrl == "https://x")
    #expect(feeds.first?.lastFetched == 100)
    let request = try #require(server.last)
    #expect(request.method == "GET")
    #expect(request.path == "/api/v1/feeds")
    #expect(request.request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
  }

  @Test func noTokenNoAuthorization() async throws {
    let (api, server) = StubServer.client(token: nil) { _ in
      (200, #"{"code":"AB12","poll_id":"p1","expires_in":300}"#)
    }
    let start = try await api.pairStart(name: "phone")
    #expect(start.pollId == "p1")
    let request = try #require(server.last)
    #expect(request.method == "POST")
    #expect(request.path == "/api/v1/pair")
    #expect(request.request.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(try request.decode(PairRequest.self).name == "phone")
  }

  @Test func keepsTheServersPathWithoutItsTrailingSlashes() async throws {
    let (api, server) = StubServer.client(base: "/pressbox//") { _ in (200, "[]") }
    _ = try await api.feeds()
    #expect(server.last?.path == "/pressbox/api/v1/feeds")
  }

  @Test func needsAServer() async {
    #expect(
      await apiError { _ = try await APIClient(server: "  ", token: nil).feeds() } == .notConfigured
    )
    #expect(
      await apiError { _ = try await APIClient(server: "example.com", token: nil).feeds() }
        == .invalidServer)
  }

  @Test(arguments: [
    (401, APIError.unauthorized), (403, .forbidden), (404, .notFound), (500, .status(500)),
  ])
  func turnsStatusesIntoErrors(status: Int, expected: APIError) async {
    let (api, _) = StubServer.client(status: status)
    #expect(await apiError { _ = try await api.feeds() } == expected)
  }

  @Test func errorsSayWhatToDo() {
    #expect(APIError.status(502).errorDescription == "The server returned HTTP 502.")
    #expect(APIError.unauthorized.errorDescription?.contains("Pair it again") == true)
  }
}

struct APIClientItemsTests {
  @Test func aFeedsUnreadAfterACursor() async throws {
    let (api, server) = StubServer.client(body: #"{"items":[],"next_cursor":"c2"}"#)
    let page = try await api.items(
      source: .feed("news"), unreadOnly: true, after: .cursor("c1"), limit: 20)
    #expect(page.next == .cursor("c2"))
    #expect(server.last?.path == "/api/v1/items")
    #expect(
      server.last?.query == ["limit": "20", "feed": "news", "unread": "true", "cursor": "c1"])
  }

  @Test func searchIgnoresUnreadOnly() async throws {
    let (api, server) = StubServer.client(body: #"{"items":[]}"#)
    _ = try await api.items(source: .all, unreadOnly: true, search: "swift")
    #expect(server.last?.query == ["limit": "100", "q": "swift"])
  }

  @Test func starredIsntFilteredByUnread() async throws {
    let (api, server) = StubServer.client(body: #"{"items":[]}"#)
    _ = try await api.items(source: .starred, unreadOnly: true)
    #expect(server.last?.query == ["limit": "100", "starred": "true"])
  }

  @Test func aTagByOffsetFromAnOldServer() async throws {
    let (api, server) = StubServer.client(body: #"{"items":[],"next_offset":200}"#)
    let page = try await api.items(source: .tag("tech"), unreadOnly: false, after: .offset(100))
    #expect(page.next == .offset(200))
    #expect(server.last?.query == ["limit": "100", "tag": "tech", "offset": "100"])
  }

  @Test func unreadEpisodes() async throws {
    let (api, server) = StubServer.client(body: #"{"items":[]}"#)
    #expect(try await api.unreadEpisodes(limit: 5).isEmpty)
    #expect(server.last?.query == ["unread": "true", "media": "true", "limit": "5"])
  }

  @Test func onlyEpisodesOrOnlyTheRest() async throws {
    let (api, server) = StubServer.client(body: #"{"items":[]}"#)
    _ = try await api.items(source: .all, unreadOnly: true, media: true)
    #expect(server.last?.query == ["limit": "100", "unread": "true", "media": "true"])
    _ = try await api.items(source: .tag("tech"), unreadOnly: false, media: false)
    #expect(server.last?.query == ["limit": "100", "tag": "tech", "media": "false"])
  }

  @Test func oneItem() async throws {
    let (api, server) = StubServer.client(
      body: #"{"id":9,"feed_id":"news","title":"Nine","published":0,"read":false,"starred":true}"#)
    let item = try await api.item(9)
    #expect(item.starred)
    #expect(server.last?.path == "/api/v1/items/9")
  }
}

struct APIClientChangeTests {
  @Test func submitsEachKindOfChange() async throws {
    let (api, server) = StubServer.client()
    try await api.submit(.read(1, true))
    try await api.submit(.starred(2, false))
    try await api.submit(.position(3, 90))
    try await api.submit(.queue([3, 1]))
    let sent = server.all
    #expect(sent.map(\.method) == ["PUT", "PUT", "PUT", "PUT"])
    #expect(
      sent.map(\.path) == [
        "/api/v1/items/1/read", "/api/v1/items/2/starred", "/api/v1/items/3/position",
        "/api/v1/queue",
      ])
    #expect(try sent[0].decode(Flag.self).value)
    #expect(try !sent[1].decode(Flag.self).value)
    #expect(try sent[2].decode(Position.self).position == 90)
    #expect(try sent[3].decode(QueueOrder.self).ids == [3, 1])
    #expect(sent[0].request.value(forHTTPHeaderField: "Content-Type") == "application/json")
  }

  @Test func marksAFeedRead() async throws {
    let (api, server) = StubServer.client(body: #"{"updated":3}"#)
    #expect(try await api.markFeedRead("news") == 3)
    #expect(server.last?.method == "POST")
    #expect(server.last?.path == "/api/v1/feeds/news/read-all")
  }

  @Test func marksAListRead() async throws {
    let (api, server) = StubServer.client(body: #"{"updated":4}"#)
    #expect(try await api.markRead(MarkRead(source: .tag("tech"), media: true)) == 4)
    #expect(server.last?.method == "POST")
    #expect(server.last?.path == "/api/v1/items/read-all")
    #expect(try server.last?.decode(MarkRead.self) == MarkRead(source: .tag("tech"), media: true))
    let body = String(decoding: try #require(server.last?.body), as: UTF8.self)
    #expect(!body.contains("feed"), "nil filters are left out")
  }

  @Test func refreshes() async throws {
    let (api, server) = StubServer.client()
    try await api.refresh()
    #expect(server.last?.method == "POST")
    #expect(server.last?.path == "/api/v1/refresh")
  }

  @Test func readsTheQueue() async throws {
    let (api, server) = StubServer.client(
      body:
        #"{"items":[{"id":4,"feed_id":"pod","title":"Four","published":0,"read":false,"starred":false}]}"#
    )
    #expect(try await api.queue().map(\.id) == [4])
    #expect(server.last?.path == "/api/v1/queue")
  }
}

struct APIClientExtrasTests {
  @Test func chapters() async throws {
    let (api, server) = StubServer.client(
      body: #"{"chapters":[{"start":0,"title":"Intro"},{"start":60,"hidden":true}]}"#)
    let chapters = try await api.chapters(7)
    #expect(chapters.map(\.id) == [0, 60])
    #expect(chapters.map(\.isHidden) == [false, true])
    #expect(server.last?.path == "/api/v1/items/7/chapters")
  }

  @Test func noChaptersFileMeansNoChapters() async throws {
    #expect(try await StubServer.client(status: 404).0.chapters(7).isEmpty)
    let (api, _) = StubServer.client(status: 500)
    #expect(await apiError { _ = try await api.chapters(7) } == .status(500))
  }

  @Test func transcript() async throws {
    let (api, _) = StubServer.client(
      body: #"{"segments":[{"start":1.5,"end":3,"speaker":"Chris","text":"Hi"}]}"#)
    #expect(try await api.transcript(7)?.segments.first?.text == "Hi")
    #expect(try await StubServer.client(status: 404).0.transcript(7) == nil)
  }

  @Test func serverVersionAndWhoIAm() async throws {
    let (api, server) = StubServer.client { request in
      request.url?.path() == "/api/v1/version"
        ? (200, #"{"version":"26.0.0","api":1}"#)
        : (200, #"{"user":"chris","admin":true}"#)
    }
    #expect(try await api.version().api == 1)
    let me = try await api.me()
    #expect(me.admin)
    #expect(me.device == nil)
    #expect(server.all.map(\.path) == ["/api/v1/version", "/api/v1/me"])
  }
}

struct APIClientPairingTests {
  @Test func pollingWaitsThenGetsTheToken() async throws {
    #expect(try await StubServer.client(status: 202).0.pairPoll("p1") == nil)
    let (api, server) = StubServer.client(body: #"{"token":"t0k","name":"phone"}"#)
    #expect(try await api.pairPoll("p1")?.token == "t0k")
    #expect(server.last?.path == "/api/v1/pair/p1")
  }

  @Test(arguments: [(404, APIError.notFound), (500, .status(500))])
  func pollingFails(status: Int, expected: APIError) async {
    let (api, _) = StubServer.client(status: status)
    #expect(await apiError { _ = try await api.pairPoll("p1") } == expected)
  }

  @Test func listsPendingPairings() async throws {
    let (api, _) = StubServer.client(body: #"[{"code":"AB12","name":"phone","requested":0}]"#)
    #expect(try await api.pairings().map(\.id) == ["AB12"])
  }

  @Test func approvesATidiedCode() async throws {
    let (api, server) = StubServer.client(body: #"{"name":"phone","user":"chris"}"#)
    let approved = try await api.approve(code: " ab12 \n", user: "  ")
    #expect(approved.user == "chris")
    #expect(server.last?.path == "/api/v1/pairings/AB12/approve")
    #expect(try server.last?.decode(ApproveRequest.self).user == nil, "a blank user is nobody")
  }

  @Test func approvesForAnotherUser() async throws {
    let (api, server) = StubServer.client(body: #"{"name":"phone","user":"sam"}"#)
    _ = try await api.approve(code: "AB12", user: " sam ")
    #expect(try server.last?.decode(ApproveRequest.self).user == "sam")
  }

  @Test func aForbiddenApproval() async {
    let (api, _) = StubServer.client(status: 403)
    #expect(await apiError { _ = try await api.approve(code: "AB12", user: "sam") } == .forbidden)
  }
}
