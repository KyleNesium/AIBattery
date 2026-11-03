import Foundation

/// Throttle-transition bookkeeping.
///
/// Stays next to its storage: the per-account `ThrottleTracker` map is a stored static on
/// the owning class, so the helpers that manage it belong with it rather than in
/// `UsageViewModel+Statics.swift`, which holds only pure, stateless helpers.
@MainActor
extension UsageViewModel {
    // MARK: - Throttle bookkeeping

    //
    // Static helpers that are pure / stateless live in `UsageViewModel+Statics.swift`.
    // The throttle tracker stays here because it depends on a stored static
    // ThrottleTracker (`throttleTracker`), which only makes sense alongside
    // the storage it manages.

    /// Throttle transition trackers — pure structs, side-effects handled here. Keyed by
    /// account id: a single global tracker read account B's healthy reading as account
    /// A's recovery, so switching throttled A → healthy B → A logged a fresh "engaged"
    /// and appended a duplicate timestamp every round trip (inflating the Insights
    /// throttle-trend rows). The signed-out / legacy path keys under `""`.
    private static var throttleTrackers: [String: ThrottleTracker] = [:]

    /// Formats reset timestamps for throttle-transition log lines.
    private static let throttleLogDateFormatter = ISO8601DateFormatter()

    /// Record a throttle event on the transition from normal → throttled for ONE account.
    /// Each distinct throttle session counts as one event regardless of duration.
    /// Also emits one structured log line on each throttle on/off transition so a
    /// stuck/false throttle state is diagnosable after the fact.
    static func recordThrottleEvent(_ rateLimits: RateLimitUsage?, accountId: String? = nil, source: String = "unknown") {
        let key = accountId ?? ""
        let tracker = throttleTrackers[key] ?? ThrottleTracker()
        let wasThrottled = tracker.wasThrottled
        let (next, timestamp) = tracker.evaluate(rateLimits)
        throttleTrackers[key] = next
        if next.wasThrottled != wasThrottled {
            let window = rateLimits?.bindingWindowLabel ?? "n/a"
            let reset = rateLimits?.bindingReset.map(Self.throttleLogDateFormatter.string(from:)) ?? "none"
            if next.wasThrottled {
                AppLogger.network.info("Throttle engaged — window=\(window, privacy: .public) reset=\(reset, privacy: .public) source=\(source, privacy: .public)")
            } else {
                AppLogger.network.info("Throttle cleared — window=\(window, privacy: .public) reset=\(reset, privacy: .public) source=\(source, privacy: .public)")
            }
        }
        if let timestamp {
            var byAccount = storedTimestampsByAccount()
            let existing = byAccount[key] ?? []
            byAccount[key] = ThrottleTracker.appendAndPrune(timestamps: existing, newTimestamp: timestamp)
            UserDefaults.standard.set(byAccount, forKey: UserDefaultsKeys.throttleTimestampsByAccount)
        }
    }

    /// Count throttle events within a given number of days, for ONE account.
    ///
    /// The store used to be a single unscoped array, so a Codex account's Insights panel
    /// reported throttles that only ever happened on a Claude account — the one
    /// cross-provider leak left in v3. (The 3.2.0 changelog says the tracker is per
    /// account: true of the state machine above, not of this store until now.)
    static func throttleCount(days: Int, accountId: String? = AccountStore.persistedActiveAccountId) -> Int {
        let timestamps = storedTimestampsByAccount()[accountId ?? ""] ?? []
        return ThrottleTracker.count(timestamps: timestamps, days: days)
    }

    /// `[accountId: [epochSeconds]]`. A value written by an older build (the unscoped
    /// array) simply does not decode here and is ignored: this is a 30-day rolling
    /// trend, so it refills itself within a day of use, and migrating one global array
    /// into an account would attribute another account's throttles to it.
    private static func storedTimestampsByAccount() -> [String: [Double]] {
        let raw = UserDefaults.standard.dictionary(forKey: UserDefaultsKeys.throttleTimestampsByAccount) ?? [:]
        return raw.compactMapValues { value in
            let parsed = ThrottleTracker.parseTimestamps(value as? [Any])
            return parsed.isEmpty ? nil : parsed
        }
    }
}
