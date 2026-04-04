import Foundation

/// Estimates 5h/7d usage percentages from local JSONL token counts when
/// Anthropic's unified rate limit headers are unavailable.
///
/// Calibration: When the API returns both utilization AND we have local
/// token counts, we derive the window's token limit and persist it.
/// Future polls use the calibrated limit to compute percentages locally.
///
/// Without calibration, shows raw token counts (no percentage).
enum LocalUsageEstimate {
    /// UserDefaults keys for calibrated limits.
    private static let fiveHourLimitKey = "aibattery_calibrated_5h_limit"
    private static let sevenDayLimitKey = "aibattery_calibrated_7d_limit"
    private static let calibratedAtKey = "aibattery_calibrated_at"

    /// Calibrated 5-hour token limit (0 = uncalibrated).
    static var fiveHourLimit: Int {
        get { UserDefaults.standard.integer(forKey: fiveHourLimitKey) }
        set { UserDefaults.standard.set(newValue, forKey: fiveHourLimitKey) }
    }

    /// Calibrated 7-day token limit (0 = uncalibrated).
    static var sevenDayLimit: Int {
        get { UserDefaults.standard.integer(forKey: sevenDayLimitKey) }
        set { UserDefaults.standard.set(newValue, forKey: sevenDayLimitKey) }
    }

    /// When the limits were last calibrated.
    static var calibratedAt: Date? {
        let ts = UserDefaults.standard.double(forKey: calibratedAtKey)
        return ts > 0 ? Date(timeIntervalSinceReferenceDate: ts) : nil
    }

    /// Whether we have calibrated limits to estimate percentages.
    static var isCalibrated: Bool {
        fiveHourLimit > 0 || sevenDayLimit > 0
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

    /// Estimate 5-hour utilization from local tokens (0–100, or nil if uncalibrated).
    static func fiveHourPercent(tokens: Int) -> Double? {
        guard fiveHourLimit > 0 else { return nil }
        return min(Double(tokens) / Double(fiveHourLimit) * 100.0, 100.0)
    }

    /// Estimate 7-day utilization from local tokens (0–100, or nil if uncalibrated).
    static func sevenDayPercent(tokens: Int) -> Double? {
        guard sevenDayLimit > 0 else { return nil }
        return min(Double(tokens) / Double(sevenDayLimit) * 100.0, 100.0)
    }

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
