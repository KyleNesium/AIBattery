import Foundation
import Security

final class KeychainReader {
    static let shared = KeychainReader()

    /// Cached API key — read from Keychain once, then reused for the app lifetime.
    /// This minimizes Keychain access to a single call at launch, reducing EDR/security
    /// tool triggers (CrowdStrike, SentinelOne, etc.) that flag repeated Keychain reads.
    private var cachedKey: String?
    private var hasAttemptedRead = false

    /// Reads the API key from macOS Keychain (service: "Claude Code").
    ///
    /// Security design:
    /// - Queries only the specific service+account, never enumerates passwords
    /// - Caches in memory after first read — Keychain is accessed exactly once
    /// - The Keychain item was created by Claude Code; macOS will prompt the user
    ///   to authorize access if this app isn't in the item's ACL
    func readAPIKey() -> String? {
        if hasAttemptedRead { return cachedKey }
        hasAttemptedRead = true

        // Specific query: service + class only. kSecMatchLimitOne prevents enumeration.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }

        // Parse the stored credential
        if let key = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
            // Direct API key (sk-ant-...) — validate format: starts with sk-, alphanumeric/hyphens/underscores, reasonable length
            if key.hasPrefix("sk-"),
               key.count >= 20,
               key.count <= 256,
               key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) {
                cachedKey = key
                return cachedKey
            }
        }

        // OAuth JSON blob with accessToken field
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let token = json["accessToken"] as? String ?? json["access_token"] as? String {
            cachedKey = token
            return cachedKey
        }

        return nil
    }

    /// Force re-read from Keychain (e.g., if the key was rotated).
    /// Call sparingly — each call hits the Keychain.
    func invalidateCache() {
        cachedKey = nil
        hasAttemptedRead = false
    }
}
