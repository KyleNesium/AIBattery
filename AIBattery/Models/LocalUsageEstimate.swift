import Foundation
import os

/// Estimates 5h/7d usage percentages from local JSONL token counts when
/// Anthropic's unified rate limit headers are unavailable.
///
/// Calibration: When the API returns both utilization AND we have local
/// token counts, we derive the window's token limit and persist it.
/// Future polls use the calibrated limit to compute percentages locally.
///
/// Without calibration, shows raw token counts (no percentage).
@MainActor
enum LocalUsageEstimate {
    /// UserDefaults keys for calibrated limits. Marked nonisolated so the
    /// nonisolated `fiveHourLimit` / `sevenDayLimit` getters can read them
    /// without crossing actor boundaries (silences Swift 6 warnings).
    nonisolated private static let fiveHourLimitKey = "aibattery_calibrated_5h_limit"
    nonisolated private static let sevenDayLimitKey = "aibattery_calibrated_7d_limit"
    private static let calibratedAtKey = "aibattery_calibrated_at"
    /// Tracks whether calibration includes cache tokens (v2.2+ methodology).
    private static let calibrationVersionKey = "aibattery_calibration_version"
    private static let currentCalibrationVersion = 2

    /// Clear stale calibrations from before cache-inclusive counting (v2.2).
    /// Called once at launch — if the stored version is older, wipe the limits.
    static func migrateIfNeeded() {
        let stored = UserDefaults.standard.integer(forKey: calibrationVersionKey)
        if stored < currentCalibrationVersion {
            fiveHourLimit = 0
            sevenDayLimit = 0
            UserDefaults.standard.removeObject(forKey: calibratedAtKey)
            UserDefaults.standard.set(currentCalibrationVersion, forKey: calibrationVersionKey)
        }
    }

    /// Calibrated 5-hour token limit (0 = uncalibrated).
    /// UserDefaults is thread-safe — reads are nonisolated for use from views/snapshots.
    nonisolated static var fiveHourLimit: Int {
        get { UserDefaults.standard.integer(forKey: fiveHourLimitKey) }
        set { UserDefaults.standard.set(newValue, forKey: fiveHourLimitKey) }
    }

    /// Calibrated 7-day token limit (0 = uncalibrated).
    nonisolated static var sevenDayLimit: Int {
        get { UserDefaults.standard.integer(forKey: sevenDayLimitKey) }
        set { UserDefaults.standard.set(newValue, forKey: sevenDayLimitKey) }
    }

    /// When the limits were last calibrated.
    static var calibratedAt: Date? {
        let ts = UserDefaults.standard.double(forKey: calibratedAtKey)
        return ts > 0 ? Date(timeIntervalSinceReferenceDate: ts) : nil
    }

    /// Whether we have calibrated limits (from API or 429 event).
    nonisolated static var isCalibrated: Bool {
        fiveHourLimit > 0 || sevenDayLimit > 0
    }

    /// Effective 5-hour limit: calibrated > plan-based > nil.
    nonisolated static var effectiveFiveHourLimit: Int? {
        if fiveHourLimit > 0 { return fiveHourLimit }
        return PlanTier.current?.estimatedFiveHourLimit
    }

    /// Effective 7-day limit: calibrated > plan-based > nil.
    nonisolated static var effectiveSevenDayLimit: Int? {
        if sevenDayLimit > 0 { return sevenDayLimit }
        return PlanTier.current?.estimatedSevenDayLimit
    }

    /// Whether the active limit comes from calibration (exact) vs plan estimate (approximate).
    nonisolated static func limitSource(for window: MetricMode) -> LimitSource? {
        switch window {
        case .fiveHour:
            if fiveHourLimit > 0 { return .calibrated }
            if PlanTier.current != nil { return .planEstimate }
            return nil
        case .sevenDay:
            if sevenDayLimit > 0 { return .calibrated }
            if PlanTier.current != nil { return .planEstimate }
            return nil
        default:
            return nil
        }
    }

    enum LimitSource {
        case calibrated
        case planEstimate
    }

    /// Calibrate limits from API utilization + local token counts.
    /// Called when the API returns valid utilization data alongside local token totals.
    ///
    /// Formula: limit = localTokens / utilization
    /// Only calibrates when utilization is between 5% and 95% (edges are noisy).
    static func calibrate(
        fiveHourUtilization: Double,
        sevenDayUtilization: Double,
        localFiveHourTokens: Int,
        localSevenDayTokens: Int
    ) {
        var updated = false
        if fiveHourUtilization >= 0.05, fiveHourUtilization <= 0.95, localFiveHourTokens > 0 {
            let derived = Int(Double(localFiveHourTokens) / fiveHourUtilization)
            // Sanity check: limit should be > 100K tokens
            if derived > 100_000 {
                fiveHourLimit = derived
                updated = true
            }
        }
        if sevenDayUtilization >= 0.05, sevenDayUtilization <= 0.95, localSevenDayTokens > 0 {
            let derived = Int(Double(localSevenDayTokens) / sevenDayUtilization)
            if derived > 100_000 {
                sevenDayLimit = derived
                updated = true
            }
        }
        if updated {
            UserDefaults.standard.set(Date().timeIntervalSinceReferenceDate, forKey: calibratedAtKey)
        }
    }

    /// Estimate 5-hour utilization from local tokens (0–100, or nil if no limit known).
    nonisolated static func fiveHourPercent(tokens: Int) -> Double? {
        guard let limit = effectiveFiveHourLimit, limit > 0 else { return nil }
        return min(Double(tokens) / Double(limit) * 100.0, 100.0)
    }

    /// Estimate 7-day utilization from local tokens (0–100, or nil if no limit known).
    nonisolated static func sevenDayPercent(tokens: Int) -> Double? {
        guard let limit = effectiveSevenDayLimit, limit > 0 else { return nil }
        return min(Double(tokens) / Double(limit) * 100.0, 100.0)
    }

    // MARK: - Latest Token Counts (for 429 calibration)

    /// Updated each refresh cycle by UsageViewModel so 429 calibration can snapshot them.
    static var latestFiveHourTokens: Int = 0
    static var latestSevenDayTokens: Int = 0

    /// Called when a 429 is received without unified headers.
    /// The 429 *may* mean the user's quota is at the real limit, but a 429 with
    /// no rate limit headers also fires for upstream incidents, IP/org blocks,
    /// and per-minute throttles — none of which carry quota signal. We must not
    /// silently ratchet a precise prior calibration *down* from such a 429.
    ///
    /// Policy: only seed an *uncalibrated* limit (0 == uncalibrated). Once
    /// `calibrate()` has run against real utilization headers, we treat that
    /// number as authoritative and never overwrite it from a header-less 429.
    /// Applies a small buffer (95%) since the 429 may fire slightly before 100%.
    static func calibrateFrom429() {
        let buffer = 0.95
        var updated = false
        if fiveHourLimit == 0, latestFiveHourTokens > 100_000 {
            let derived = Int(Double(latestFiveHourTokens) / buffer)
            fiveHourLimit = derived
            updated = true
            AppLogger.network.info("429 seeded uncalibrated 5h limit: \(derived) tokens")
        }
        if sevenDayLimit == 0, latestSevenDayTokens > 100_000 {
            let derived = Int(Double(latestSevenDayTokens) / buffer)
            sevenDayLimit = derived
            updated = true
            AppLogger.network.info("429 seeded uncalibrated 7d limit: \(derived) tokens")
        }
        if updated {
            UserDefaults.standard.set(Date().timeIntervalSinceReferenceDate, forKey: calibratedAtKey)
        } else {
            AppLogger.network.info("429 calibration skipped — limits already set or local tokens too low")
        }
    }

    // MARK: - Manual Overrides

    /// Allow user to manually set their 5-hour token limit.
    static func setManualFiveHourLimit(_ limit: Int) {
        fiveHourLimit = max(limit, 0)
        UserDefaults.standard.set(Date().timeIntervalSinceReferenceDate, forKey: calibratedAtKey)
    }

    /// Allow user to manually set their 7-day token limit.
    static func setManualSevenDayLimit(_ limit: Int) {
        sevenDayLimit = max(limit, 0)
        UserDefaults.standard.set(Date().timeIntervalSinceReferenceDate, forKey: calibratedAtKey)
    }
}
