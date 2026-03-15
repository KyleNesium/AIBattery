import Foundation
import os

/// Low-level macOS Keychain CRUD operations for AIBattery's service entries.
/// Extracted from OAuthManager to keep file sizes manageable.
enum KeychainHelper {
    private static let keychainService = "AIBattery"

    static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
    }

    static func set(account: String, value: String) {
        let data = Data(value.utf8)

        // Try to update existing item first
        let searchQuery = baseQuery(account: account)
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
        ]
        let updateStatus = SecItemUpdate(searchQuery as CFDictionary, updateAttrs as CFDictionary)

        if updateStatus == errSecItemNotFound {
            add(searchQuery: searchQuery, data: data, account: account, logPrefix: "Keychain")
        } else if updateStatus != errSecSuccess {
            AppLogger.oauth.error("Keychain update failed for \(account, privacy: .public): \(updateStatus)")
            // Fallback: delete and re-add
            SecItemDelete(searchQuery as CFDictionary)
            add(searchQuery: searchQuery, data: data, account: account, logPrefix: "Keychain fallback")
        }
    }

    static func get(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status != errSecSuccess && status != errSecItemNotFound {
            AppLogger.oauth.error("Keychain read failed for \(account, privacy: .public): \(status)")
        }
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    // MARK: - Internal

    private static func add(searchQuery: [String: Any], data: Data, account: String, logPrefix: String) {
        var addQuery = searchQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            AppLogger.oauth.error("\(logPrefix, privacy: .public) add failed for \(account, privacy: .public): \(status)")
        }
    }
}
