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
            let existing = ThrottleTracker.parseTimestamps(
                UserDefaults.standard.array(forKey: UserDefaultsKeys.throttleTimestamps)
            )
            let updated = ThrottleTracker.appendAndPrune(timestamps: existing, newTimestamp: timestamp)
            UserDefaults.standard.set(updated, forKey: UserDefaultsKeys.throttleTimestamps)
        }
    }

    /// Count throttle events within a given number of days.
    static func throttleCount(days: Int) -> Int {
        let timestamps = ThrottleTracker.parseTimestamps(
            UserDefaults.standard.array(forKey: UserDefaultsKeys.throttleTimestamps)
        )
        return ThrottleTracker.count(timestamps: timestamps, days: days)
    }
}
