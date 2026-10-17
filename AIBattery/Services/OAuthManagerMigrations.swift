import Foundation

/// One-time launch migrations for the Keychain layout.
///
/// Split out of `OAuthManager.swift`, which had grown past the 800-line ceiling in
/// CLAUDE.md. These run from `init` and each is gated so it does its work once: the
/// account layout moved from a single unprefixed entry to one per account, stale
/// `accessToken_` / `expiresAt_` items had to be swept, and the remaining items were
/// re-created with `ThisDeviceOnly` accessibility so iCloud Keychain stops syncing
/// refresh tokens to other devices.
@MainActor
extension OAuthManager {
    // MARK: - Migration from Single-Account Format

    /// One-time migration: moves legacy Keychain entries (unprefixed) to the new prefixed format.
    func migrateFromLegacy() {
        // Already migrated — accounts exist
        guard accountStore.accounts.isEmpty else { return }

        // Check for legacy (unprefixed) Keychain entries
        let legacyRefresh = KeychainHelper.get(account: "refreshToken")
        guard legacyRefresh != nil else { return }

        AppLogger.oauth.info("Migrating legacy single-account Keychain entries")

        let tempId = "pending-\(UUID().uuidString)"
        let record = AccountRecord(
            id: tempId,
            displayName: nil,
            billingType: UserDefaults.standard.string(forKey: UserDefaultsKeys.plan),
            addedAt: Date()
        )

        // Only persist the refresh token (access token will be re-derived on launch).
        // Verify the new entry before deleting the legacy one — if the write fails,
        // keep the legacy entries intact and retry the migration next launch.
        if let value = KeychainHelper.get(account: "refreshToken") {
            guard Self.setAndVerify(account: "refreshToken_\(tempId)", value: value) else {
                AppLogger.oauth.error("Legacy Keychain migration failed — keeping legacy entries for retry next launch")
                return
            }
        }
        // expiresAt goes to UserDefaults (not a secret)
        if let expiresStr = KeychainHelper.get(account: "expiresAt"),
           let interval = Double(expiresStr) {
            UserDefaults.standard.set(interval,
                                      forKey: UserDefaultsKeys.tokenExpiresAtPrefix + tempId)
        }
        // Clean up all legacy unprefixed entries
        for key in ["accessToken", "refreshToken", "expiresAt"] {
            KeychainHelper.delete(account: key)
        }

        accountStore.add(record)
        accountStore.setActive(id: tempId)
    }

    // MARK: - Migration: Remove Stale Keychain Items

    /// Removes accessToken and expiresAt from Keychain (they're no longer stored
    /// there). Moves expiresAt to UserDefaults if not already present.
    ///
    /// Runs once, like `migrateKeychainAccessibility`. It used to run on every launch,
    /// spending two `SecItemDelete` calls and a `SecItemCopyMatching` per account to
    /// re-delete items that had been gone since the first launch after the upgrade.
    /// Keychain calls are slow and can prompt, which is exactly what the one-item-per-
    /// account rule elsewhere in this file exists to avoid.
    func migrateStaleKeychainItems() {
        let migrationKey = "aibattery_staleKeychainItemsMigrated"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: migrationKey) }

        for account in accountStore.accounts {
            let accountId = account.id

            // Move expiresAt from Keychain to UserDefaults if present
            let udKey = UserDefaultsKeys.tokenExpiresAtPrefix + accountId
            if UserDefaults.standard.double(forKey: udKey) == 0 {
                if let expiresStr = KeychainHelper.get(account: "expiresAt_\(accountId)"),
                   let interval = Double(expiresStr) {
                    UserDefaults.standard.set(interval, forKey: udKey)
                }
            }

            // Remove stale Keychain items (accessToken + expiresAt)
            KeychainHelper.delete(account: "accessToken_\(accountId)")
            KeychainHelper.delete(account: "expiresAt_\(accountId)")
        }
    }

    // MARK: - Migration: Keychain ThisDeviceOnly Accessibility

    /// One-time migration: re-creates Keychain items with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
    /// The old flag (`kSecAttrAccessibleWhenUnlocked`) allows iCloud Keychain to sync refresh tokens
    /// to other Apple devices. Keychain doesn't support updating `kSecAttrAccessible` in-place, so
    /// we delete and re-add each item. Only runs once (tracked via UserDefaults flag).
    func migrateKeychainAccessibility() {
        let migrationKey = "aibattery_keychainThisDeviceOnlyMigrated"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        // Accessibility can't be updated in place, so each item must be deleted and
        // re-added — a window where a failed re-add would destroy the refresh token.
        // Hardening: verify the re-add by reading the value back, retry once on
        // failure, and only mark the migration done when EVERY account verified.
        // Leaving the flag unset means the next launch retries instead of silently
        // signing the user out forever.
        var allVerified = true
        for account in accountStore.accounts {
            let keychainAccount = "refreshToken_\(account.id)"
            guard let value = KeychainHelper.get(account: keychainAccount) else { continue }
            KeychainHelper.delete(account: keychainAccount)
            if !Self.setAndVerify(account: keychainAccount, value: value),
               !Self.setAndVerify(account: keychainAccount, value: value) {
                allVerified = false
                AppLogger.oauth.error("Keychain accessibility migration failed for \(account.id, privacy: .public) — will retry next launch")
            }
        }

        guard allVerified else { return }
        UserDefaults.standard.set(true, forKey: migrationKey)
        AppLogger.oauth.info("Migrated Keychain items to ThisDeviceOnly accessibility")
    }

    /// Write a Keychain value and confirm it round-trips. A `set` that reports
    /// success but doesn't read back identical is treated as a failure.
    static func setAndVerify(account: String, value: String) -> Bool {
        KeychainHelper.set(account: account, value: value)
            && KeychainHelper.get(account: account) == value
    }
}
