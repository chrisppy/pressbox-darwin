// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import Foundation

extension URL {
  /// Artwork from a feed or episode. App Transport Security lets the app
  /// load plain http only from the local network, so artwork elsewhere is
  /// asked for over https: most hosts serve both, and a tile with no
  /// artwork shows its title instead.
  init?(artwork: String?) {
    guard let artwork, var parts = URLComponents(string: artwork) else { return nil }
    if parts.scheme?.lowercased() == "http", let host = parts.host, !Self.isLocal(host) {
      parts.scheme = "https"
      // Port 80 is http's; https wants its own.
      if parts.port == 80 { parts.port = nil }
    }
    guard let url = parts.url else { return nil }
    self = url
  }

  /// What `NSAllowsLocalNetworking` allows over http: unqualified names,
  /// `.local` names, and IP addresses.
  private static func isLocal(_ host: String) -> Bool {
    let host = host.lowercased()
    return !host.contains(".") || host.hasSuffix(".local") || host.contains(":")
      || host.split(separator: ".").allSatisfy { UInt8($0) != nil }
  }
}
