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

    /// Returns whether the value actually landed in the Keychain. Callers that
    /// delete-then-set (the accessibility migration) MUST check this — treating
    /// a failed set as success after a delete destroys the stored token.
    @discardableResult
    static func set(account: String, value: String) -> Bool {
        let data = Data(value.utf8)

        // Try to update existing item first
        let searchQuery = baseQuery(account: account)
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
        ]
        let updateStatus = SecItemUpdate(searchQuery as CFDictionary, updateAttrs as CFDictionary)

        if updateStatus == errSecItemNotFound {
            return add(searchQuery: searchQuery, data: data, account: account, logPrefix: "Keychain")
        } else if updateStatus != errSecSuccess {
            AppLogger.oauth.error("Keychain update failed for \(account, privacy: .public): \(updateStatus)")
            // Fallback: delete and re-add
            SecItemDelete(searchQuery as CFDictionary)
            return add(searchQuery: searchQuery, data: data, account: account, logPrefix: "Keychain fallback")
        }
        return true
    }

    /// Outcome of a Keychain read. `failed` is not "no item": the item may well exist but
    /// couldn't be read right now (a prompt cancelled by sleep, a locked keychain), so a
    /// caller holding a sign-in must not treat it as signed out.
    enum ReadResult: Equatable, Sendable {
        case found(String)
        case notFound
        case failed(OSStatus)
    }

    static func read(account: String) -> ReadResult {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else { return .notFound }
            return .found(value)
        case errSecItemNotFound:
            return .notFound
        default:
            AppLogger.oauth.error("Keychain read failed for \(account, privacy: .public): \(status)")
            return .failed(status)
        }
    }

    static func get(account: String) -> String? {
        if case let .found(value) = read(account: account) {
            return value
        }
        return nil
    }

    static func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    // MARK: - Internal

    private static func add(searchQuery: [String: Any], data: Data, account: String, logPrefix: String) -> Bool {
        var addQuery = searchQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            AppLogger.oauth.error("\(logPrefix, privacy: .public) add failed for \(account, privacy: .public): \(status)")
        }
        return status == errSecSuccess
    }
}
