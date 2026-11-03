import Foundation

/// Every account-id-keyed UserDefaults key, in one place.
///
/// A Claude account is created under a temporary `pending-<uuid>` id and renamed once
/// the first API call returns the real org id. Each store that had learned something
/// under the pending id needed its own migration, and the ones added later were simply
/// missed: calibration, the observed-model probe list and the last working probe model
/// all stayed under the dead key, so a resolved account started uncalibrated and
/// re-probed from scratch, while the orphans were never pruned.
///
/// Registering a key shape here is what makes it follow the account. Stores with their
/// own in-memory state (`TokenLedger`, `RateLimitFetcher`, the Keychain) keep their own
/// `migrate(from:to:)` — they have more to move than a defaults key — and are called
/// alongside this from the single resolution point in `OAuthManager`.
@MainActor
enum AccountIdentityRegistry {
    /// Keys written as `"<base>_<accountId>"`.
    static let suffixedBases: [String] = [
        "aibattery_calibrated_5h_limit",
        "aibattery_calibrated_7d_limit",
        "aibattery_calibrated_at",
    ]

    /// Keys written as `"<prefix><accountId>"`.
    ///
    /// `RateLimitFetcher.persistKeyPrefix` is deliberately absent: its blob is mirrored
    /// by an in-memory cache, so it migrates through `RateLimitFetcher.migrate(from:to:)`
    /// instead and would be moved twice if it were listed here.
    static let prefixes: [String] = [
        RateLimitFetcher.observedModelsKeyPrefix,
        RateLimitFetcher.workingModelKeyPrefix,
        CodexRateLimitFetcher.persistKeyPrefix,
    ]

    /// Every registered key for one account id.
    static func keys(for accountId: String) -> [String] {
        suffixedBases.map { "\($0)_\(accountId)" } + prefixes.map { $0 + accountId }
    }

    /// Move every registered key from one account id to another. The destination wins
    /// when it already has a value (a fresh write landed first); the source key is
    /// always removed, so nothing orphans under the dead id.
    static func migrate(from oldId: String, to newId: String, defaults: UserDefaults = .standard) {
        guard oldId != newId, !oldId.isEmpty, !newId.isEmpty else { return }
        for (oldKey, newKey) in zip(keys(for: oldId), keys(for: newId)) {
            if let value = defaults.object(forKey: oldKey) {
                if defaults.object(forKey: newKey) == nil {
                    defaults.set(value, forKey: newKey)
                }
                defaults.removeObject(forKey: oldKey)
            }
        }
    }
}
