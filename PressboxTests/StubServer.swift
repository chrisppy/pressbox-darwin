// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@testable import Pressbox

/// A fake pressboxd for `APIClient`: a `URLProtocol` that answers each request
/// from a closure, with no network. Every client gets its own made-up host, so
/// tests running in parallel don't see each other's requests.
final class StubServer: URLProtocol {
  /// The status and JSON body to answer a request with.
  typealias Reply = @Sendable (URLRequest) -> (Int, String)

  /// A request the client sent, with its body.
  struct Request: Sendable {
    let request: URLRequest
    let body: Data?

    var method: String? { request.httpMethod }
    var path: String? { request.url?.path() }
    var query: [String: String] {
      let items =
        request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
        .queryItems ?? []
      return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, b in b })
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
      try JSONDecoder().decode(type, from: body ?? Data())
    }
  }

  /// What one client sent.
  final class Log: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [Request] = []

    fileprivate func add(_ request: Request) {
      lock.lock()
      defer { lock.unlock() }
      requests.append(request)
    }

    var all: [Request] {
      lock.lock()
      defer { lock.unlock() }
      return requests
    }

    var last: Request? { all.last }
  }

  private static let lock = NSLock()
  nonisolated(unsafe) private static var hosts: [String: (Reply, Log)] = [:]

  /// A client of a new fake server, at `base` under its made-up host.
  static func client(
    token: String? = "secret", base: String = "", reply: @escaping Reply
  ) -> (APIClient, Log) {
    let host = "s\(UUID().uuidString.lowercased().prefix(8)).test"
    let log = Log()
    lock.lock()
    hosts[host] = (reply, log)
    lock.unlock()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubServer.self]
    var api = APIClient(server: "http://\(host)\(base)", token: token)
    api.session = URLSession(configuration: configuration)
    return (api, log)
  }

  /// A client of a server that answers everything with `status` and `body`.
  static func client(status: Int = 200, body: String = "{}") -> (APIClient, Log) {
    client { _ in (status, body) }
  }

  override class func canInit(with request: URLRequest) -> Bool { true }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let host = request.url?.host() ?? ""
    Self.lock.lock()
    let found = Self.hosts[host]
    Self.lock.unlock()
    guard let url = request.url, let found else {
      client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
      return
    }
    let (reply, log) = found
    log.add(Request(request: request, body: Self.body(of: request)))
    let (status, body) = reply(request)
    let response = HTTPURLResponse(
      url: url, statusCode: status, httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}

  /// URLSession hands a protocol the body as a stream, not `httpBody`.
  private static func body(of request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      if count <= 0 { break }
      data.append(buffer, count: count)
    }
    return data
  }
}
