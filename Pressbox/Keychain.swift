// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import Foundation
import Security

/// Stores the API token in the keychain rather than in UserDefaults.
///
/// It is readable after the first unlock (not behind Face ID) so the
/// background refresh can update the unread badge; the Face ID lock guards
/// the app's UI instead. It never leaves this device.
enum Keychain {
  private static let service = "org.red-oxide.pressbox"
  private static let account = "api-token"

  private static var query: [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    #if os(macOS)
      // The same keychain iOS uses, with the same accessibility rules,
      // rather than the older file-based macOS keychain.
      query[kSecUseDataProtectionKeychain as String] = true
    #endif
    return query
  }

  static func token() -> String? {
    var q = query
    q[kSecReturnData as String] = true
    q[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: AnyObject?
    guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  static func setToken(_ token: String) {
    SecItemDelete(query as CFDictionary)
    let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    var q = query
    q[kSecValueData as String] = Data(trimmed.utf8)
    q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    SecItemAdd(q as CFDictionary, nil)
  }
}
