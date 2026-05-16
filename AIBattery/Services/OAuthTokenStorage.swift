import Foundation

/// Manages persistence of OAuth credentials for a given account ID.
///
/// Split out from `OAuthManager` as part of the v2.3 file-split sprint to keep
/// the storage-concerns surface separate from the auth-flow logic.
///
/// Storage layout:
/// - **Refresh token** → macOS Keychain under `refreshToken_<accountId>`
/// - **Access token** → not persisted; re-derived from the refresh token on
///   next launch (short-lived ~1h secret, no value in persisting)
/// - **Expiry timestamp** → `UserDefaults` under `tokenExpiresAtPrefix +
///   accountId` (not a secret; survives device locks/sleep)
///
/// Keychain footprint is intentionally minimal — only one item per account —
/// to keep the Sparkle update prompt count at most 1 per account when the
/// ad-hoc signing identity changes.
enum OAuthTokenStorage {
    /// In-memory representation of an account's token state.
    struct AccountTokens {
        var accessToken: String?
        var refreshToken: String?
        var expiresAt: Date?
    }

    /// Persist the refresh token (Keychain) and expiry (UserDefaults) for an account.
    /// The access token is intentionally NOT persisted.
    static func save(_ tokens: AccountTokens, for accountId: String) {
        if let refresh = tokens.refreshToken {
            KeychainHelper.set(account: "refreshToken_\(accountId)", value: refresh)
        }
        if let expires = tokens.expiresAt {
            UserDefaults.standard.set(
                expires.timeIntervalSince1970,
                forKey: UserDefaultsKeys.tokenExpiresAtPrefix + accountId
            )
        }
    }

    /// Load the persisted state for an account. The returned `accessToken` is
    /// always `nil` — callers must refresh via the refresh token on first use.
    static func load(for accountId: String) -> AccountTokens {
        let refresh = KeychainHelper.get(account: "refreshToken_\(accountId)")
        var expires: Date?
        let interval = UserDefaults.standard.double(
            forKey: UserDefaultsKeys.tokenExpiresAtPrefix + accountId
        )
        if interval > 0 {
            expires = Date(timeIntervalSince1970: interval)
        }
        return AccountTokens(accessToken: nil, refreshToken: refresh, expiresAt: expires)
    }

    /// Delete all persisted state for an account, including legacy entries
    /// that earlier versions may have stored under `accessToken_*` or
    /// `expiresAt_*` Keychain keys.
    static func delete(for accountId: String) {
        KeychainHelper.delete(account: "refreshToken_\(accountId)")
        UserDefaults.standard.removeObject(
            forKey: UserDefaultsKeys.tokenExpiresAtPrefix + accountId
        )
        // Legacy cleanup — older versions stored these in Keychain.
        KeychainHelper.delete(account: "accessToken_\(accountId)")
        KeychainHelper.delete(account: "expiresAt_\(accountId)")
    }
}
