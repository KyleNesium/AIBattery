import Foundation

/// One-time launch migrations for the Keychain layout.
///
/// Split out of `OAuthManager.swift`, which had grown past the 800-line ceiling in
/// CLAUDE.md. These run from `init` and each is gated so it does its work once: the
/// account layout moved from a single unprefixed entry to one per account, and stale
/// `accessToken_` / `expiresAt_` items had to be swept.
///
/// A third migration re-created each per-account item with `ThisDeviceOnly` accessibility
/// by deleting it and adding it back. It was removed in 3.5.0: a crash between the two
/// steps destroyed the only copy of the token, and it is no longer needed. `RefreshTokenVault`
/// moves each token into an item that is created `ThisDeviceOnly`, and deletes the old
/// item only after the new one has read back.
@MainActor
extension OAuthManager {
    // MARK: - Migration from Single-Account Format

    /// One-time migration: moves legacy Keychain entries (unprefixed) to the new prefixed format.
    ///
    /// The order matters, because each step can be the last one that runs: write and verify
    /// the new entry, register the account, mark the migration done, and only then delete
    /// the old entries. A crash at any point leaves a sign-in the next launch can find. The
    /// done-flag is what makes a leftover old entry harmless: without it, a user who later
    /// signed out of every account would have that stale token migrated back in.
    func migrateFromLegacy() {
        let migrationKey = "aibattery_legacyKeychainLayoutMigrated"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        // Already migrated — accounts exist
        guard accountStore.accounts.isEmpty else { return }

        // Read the legacy (unprefixed) entry once. A second read could fail where the first
        // succeeded (a prompt answered differently), and the migration then registered an
        // account with no token.
        guard let value = KeychainHelper.get(account: "refreshToken") else { return }

        AppLogger.oauth.info("Migrating legacy single-account Keychain entries")

        let tempId = "pending-\(UUID().uuidString)"
        let record = AccountRecord(
            id: tempId,
            displayName: nil,
            billingType: UserDefaults.standard.string(forKey: UserDefaultsKeys.plan),
            addedAt: Date()
        )

        // Only persist the refresh token (access token will be re-derived on launch).
        // If the write does not verify, keep everything as it was and retry next launch.
        guard Self.setAndVerify(account: "refreshToken_\(tempId)", value: value) else {
            AppLogger.oauth.error("Legacy Keychain migration failed — keeping legacy entries for retry next launch")
            return
        }
        // expiresAt goes to UserDefaults (not a secret)
        if let expiresStr = KeychainHelper.get(account: "expiresAt"),
           let interval = Double(expiresStr) {
            UserDefaults.standard.set(interval,
                                      forKey: UserDefaultsKeys.tokenExpiresAtPrefix + tempId)
        }

        accountStore.add(record)
        accountStore.setActive(id: tempId)
        UserDefaults.standard.set(true, forKey: migrationKey)

        // Clean up all legacy unprefixed entries
        for key in ["accessToken", "refreshToken", "expiresAt"] {
            KeychainHelper.delete(account: key)
        }
    }

    // MARK: - Migration: Remove Stale Keychain Items

    /// Removes accessToken and expiresAt from Keychain (they're no longer stored
    /// there). Moves expiresAt to UserDefaults if not already present.
    ///
    /// Runs once. It used to run on every launch,
    /// spending two `SecItemDelete` calls and a `SecItemCopyMatching` per account to
    /// re-delete items that had been gone since the first launch after the upgrade.
    /// Keychain calls are slow and can prompt, which is exactly what keeping every token in
    /// one item (`RefreshTokenVault`) exists to avoid.
    func migrateStaleKeychainItems() {
        let migrationKey = "aibattery_staleKeychainItemsMigrated"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: migrationKey) }

        for account in accountStore.accounts {
            let accountId = account.id

            // Move expiresAt from Keychain to UserDefaults if present
            let udKey = UserDefaultsKeys.tokenExpiresAtPrefix + accountId
            if UserDefaults.standard.double(forKey: udKey) == 0, let expiresStr = KeychainHelper.get(account: "expiresAt_\(accountId)"),
               let interval = Double(expiresStr) {
                UserDefaults.standard.set(interval, forKey: udKey)
            }

            // Remove stale Keychain items (accessToken + expiresAt)
            KeychainHelper.delete(account: "accessToken_\(accountId)")
            KeychainHelper.delete(account: "expiresAt_\(accountId)")
        }
    }

    /// Write a Keychain value and confirm it round-trips. A `set` that reports
    /// success but doesn't read back identical is treated as a failure.
    static func setAndVerify(account: String, value: String) -> Bool {
        KeychainHelper.set(account: account, value: value)
            && KeychainHelper.get(account: account) == value
    }
}
