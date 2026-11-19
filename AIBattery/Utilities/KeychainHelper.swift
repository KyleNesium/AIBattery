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

    /// Returns whether the value actually landed in the Keychain.
    @discardableResult
    static func set(account: String, value: String) -> Bool {
        store(account: account, value: value) == errSecSuccess
    }

    /// Writes the value and returns the Keychain status, so a caller can tell a refusal
    /// (`errSecUserCanceled`, `errSecAuthFailed`) from a failure worth retrying.
    ///
    /// A failed update leaves the existing item as it was. Until 3.5.0 it was deleted and
    /// added again; a crash between the two, or a failed add, lost the value. That value is
    /// now every account's refresh token, so the old copy stays and the caller retries.
    static func store(account: String, value: String) -> OSStatus {
        let data = Data(value.utf8)

        // Try to update existing item first
        let searchQuery = baseQuery(account: account)
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
        ]
        let updateStatus = SecItemUpdate(searchQuery as CFDictionary, updateAttrs as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var addQuery = searchQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                AppLogger.oauth.error("Keychain add failed for \(account, privacy: .public): \(addStatus)")
            }
            return addStatus
        }
        if updateStatus != errSecSuccess {
            AppLogger.oauth.error("Keychain update failed for \(account, privacy: .public): \(updateStatus)")
        }
        return updateStatus
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

    /// Deny or Cancel on a Keychain prompt. Trying again would only raise the prompt again,
    /// so nothing retries on its own after one of these.
    static func isRefusal(_ status: OSStatus) -> Bool {
        status == errSecUserCanceled || status == errSecAuthFailed
    }

    /// Returns whether the item is gone: deleted, or never there. macOS refuses a delete
    /// from a build the item has not approved, so false means it is still in the Keychain.
    @discardableResult
    static func delete(account: String) -> Bool {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
