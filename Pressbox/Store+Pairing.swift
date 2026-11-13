// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import Foundation

/// Pairing: this device with the server, and approving other devices.
extension Store {
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
}
