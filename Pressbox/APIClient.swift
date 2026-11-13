// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import Foundation

enum APIError: LocalizedError {
  case notConfigured
  case invalidServer
  case unauthorized
  case forbidden
  case notFound
  case status(Int)

  var errorDescription: String? {
    switch self {
    case .notConfigured: "Set the server address in Settings."
    case .invalidServer: "The server address isn't a valid URL."
    case .unauthorized: "The server rejected this device's token. Pair it again in Settings."
    case .forbidden: "Only admins can approve devices for other users."
    case .notFound: "Not found. The code may be wrong or expired."
    case .status(let code): "The server returned HTTP \(code)."
    }
  }
}

/// Talks to pressboxd's HTTP API.
struct APIClient: Sendable {
  let server: String
  let token: String?

  static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
  }()

  private func url(_ path: String, query: [URLQueryItem] = []) throws -> URL {
    let base = server.trimmingCharacters(in: .whitespaces)
    guard !base.isEmpty else { throw APIError.notConfigured }
    guard var components = URLComponents(string: base), components.scheme != nil else {
      throw APIError.invalidServer
    }
    components.path =
      components.path.replacingOccurrences(of: "/+$", with: "", options: .regularExpression) + path
    if !query.isEmpty { components.queryItems = query }
    guard let url = components.url else { throw APIError.invalidServer }
    return url
  }

  /// Sends a request and returns the body and HTTP status.
  private func raw(
    _ method: String, _ path: String, query: [URLQueryItem] = [], body: Encodable? = nil
  ) async throws -> (Data, Int) {
    var request = URLRequest(url: try url(path, query: query))
    request.httpMethod = method
    request.timeoutInterval = 20
    if let token, !token.isEmpty {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONEncoder().encode(body)
    }
    let (data, response) = try await URLSession.shared.data(for: request)
    return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
  }

  private func send(
    _ method: String, _ path: String, query: [URLQueryItem] = [], body: Encodable? = nil
  ) async throws -> Data {
    let (data, status) = try await raw(method, path, query: query, body: body)
    switch status {
    case 200..<300: return data
    case 401: throw APIError.unauthorized
    case 403: throw APIError.forbidden
    case 404: throw APIError.notFound
    default: throw APIError.status(status)
    }
  }

  private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
    try Self.decoder.decode(type, from: data)
  }

  func feeds() async throws -> [Feed] {
    try decode([Feed].self, try await send("GET", "/api/v1/feeds"))
  }

  func items(
    source: Source, unreadOnly: Bool, search: String? = nil, after next: NextPage? = nil,
    limit: Int = 100
  ) async throws -> ItemPage {
    var query = [URLQueryItem(name: "limit", value: String(limit))]
    switch source {
    case .all: break
    case .starred: query.append(URLQueryItem(name: "starred", value: "true"))
    case .feed(let id): query.append(URLQueryItem(name: "feed", value: id))
    case .tag(let tag): query.append(URLQueryItem(name: "tag", value: tag))
    }
    if let search, !search.isEmpty {
      query.append(URLQueryItem(name: "q", value: search))
    } else if unreadOnly && source != .starred {
      query.append(URLQueryItem(name: "unread", value: "true"))
    }
    switch next {
    case .cursor(let cursor): query.append(URLQueryItem(name: "cursor", value: cursor))
    case .offset(let offset): query.append(URLQueryItem(name: "offset", value: String(offset)))
    case nil: break
    }
    return try decode(ItemPage.self, try await send("GET", "/api/v1/items", query: query))
  }

  /// The newest unread episodes (items with media), newest first.
  func unreadEpisodes(limit: Int) async throws -> [Item] {
    let query = [
      URLQueryItem(name: "unread", value: "true"), URLQueryItem(name: "media", value: "true"),
      URLQueryItem(name: "limit", value: String(limit)),
    ]
    return try decode(ItemPage.self, try await send("GET", "/api/v1/items", query: query)).items
  }

  func item(_ id: Int64) async throws -> Item {
    try decode(Item.self, try await send("GET", "/api/v1/items/\(id)"))
  }

  func setRead(_ id: Int64, _ value: Bool) async throws {
    _ = try await send("PUT", "/api/v1/items/\(id)/read", body: Flag(value: value))
  }

  func setStarred(_ id: Int64, _ value: Bool) async throws {
    _ = try await send("PUT", "/api/v1/items/\(id)/starred", body: Flag(value: value))
  }

  /// Saves where playback of an item's media stopped, in seconds.
  func setPosition(_ id: Int64, _ position: Int) async throws {
    _ = try await send("PUT", "/api/v1/items/\(id)/position", body: Position(position: position))
  }

  /// The Up Next queue, in order. Throws `.notFound` from servers without one.
  func queue() async throws -> [Item] {
    try decode(Queue.self, try await send("GET", "/api/v1/queue")).items
  }

  /// Replaces the Up Next queue with these items, in order.
  func setQueue(_ ids: [Int64]) async throws {
    _ = try await send("PUT", "/api/v1/queue", body: QueueOrder(ids: ids))
  }

  /// An item's chapters; none if it has no chapters file.
  func chapters(_ id: Int64) async throws -> [Chapter] {
    do {
      return try decode(Chapters.self, try await send("GET", "/api/v1/items/\(id)/chapters"))
        .chapters
    } catch APIError.notFound {
      return []
    }
  }

  /// An item's transcript; `nil` if it has none.
  func transcript(_ id: Int64) async throws -> Transcript? {
    do {
      return try decode(Transcript.self, try await send("GET", "/api/v1/items/\(id)/transcript"))
    } catch APIError.notFound {
      return nil
    }
  }

  func markFeedRead(_ feed: String) async throws -> Int {
    let id = feed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? feed
    let data = try await send("POST", "/api/v1/feeds/\(id)/read-all")
    return try decode(Updated.self, data).updated
  }

  func refresh() async throws {
    _ = try await send("POST", "/api/v1/refresh")
  }

  // MARK: Pairing

  /// Asks the server to pair this device; show the returned code to the user.
  func pairStart(name: String) async throws -> PairStart {
    try decode(
      PairStart.self, try await send("POST", "/api/v1/pair", body: PairRequest(name: name)))
  }

  /// The token once approved, `nil` while still waiting. Throws `.notFound`
  /// if the request was denied or expired.
  func pairPoll(_ pollId: String) async throws -> PairApproved? {
    let (data, status) = try await raw("GET", "/api/v1/pair/\(pollId)")
    switch status {
    case 200: return try decode(PairApproved.self, data)
    case 202: return nil
    case 404: throw APIError.notFound
    default: throw APIError.status(status)
    }
  }

  func pairings() async throws -> [PendingPairing] {
    try decode([PendingPairing].self, try await send("GET", "/api/v1/pairings"))
  }

  func version() async throws -> ServerVersion {
    try decode(ServerVersion.self, try await send("GET", "/api/v1/version"))
  }

  func me() async throws -> Me {
    try decode(Me.self, try await send("GET", "/api/v1/me"))
  }

  /// Approves a pairing code, for `user` if given (admins only).
  func approve(code: String, user: String? = nil) async throws -> Approved {
    let code = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    let id = code.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? code
    let user = user?.trimmingCharacters(in: .whitespaces)
    let body = ApproveRequest(user: (user?.isEmpty ?? true) ? nil : user)
    return try decode(
      Approved.self, try await send("POST", "/api/v1/pairings/\(id)/approve", body: body))
  }
}
