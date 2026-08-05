import Foundation
import os

/// Estimates 5h/7d usage percentages from local JSONL token counts when
/// Anthropic's unified rate limit headers are unavailable.
///
/// Calibration: When the API returns both utilization AND we have local
/// token counts, we derive the window's token limit and persist it.
/// Future polls use the calibrated limit to compute percentages locally.
///
/// All calibration state is **per account** (keys suffixed with the account ID):
/// with mixed plan tiers, one account's calibration must not misprice another's
/// fallback estimates. Callers that don't pass an account ID get the persisted
/// active account — every UI read path renders the active account's data.
///
/// Without calibration, shows raw token counts (no percentage).
@MainActor
enum LocalUsageEstimate {
    /// Base UserDefaults keys for calibrated limits — suffixed per account via
    /// `scopedKey`. Marked nonisolated so the nonisolated limit getters can read
    /// them without crossing actor boundaries (silences Swift 6 warnings).
    nonisolated private static let fiveHourLimitKeyBase = "aibattery_calibrated_5h_limit"
    nonisolated private static let sevenDayLimitKeyBase = "aibattery_calibrated_7d_limit"
    nonisolated private static let calibratedAtKeyBase = "aibattery_calibrated_at"
    /// Tracks whether calibration includes cache tokens (v2.2+ methodology).
    private static let calibrationVersionKey = "aibattery_calibration_version"
    private static let currentCalibrationVersion = 2
    /// One-time move of the legacy global calibration keys to the active account.
    private static let perAccountMigratedKey = "aibattery_calibration_perAccount_migrated"

    /// Per-account key: `{base}_{accountId}`. A nil account (signed out) falls
    /// back to the legacy global key so the estimate still works pre-login.
    nonisolated private static func scopedKey(_ base: String, _ accountId: String?) -> String {
        guard let accountId, !accountId.isEmpty else { return base }
        return "\(base)_\(accountId)"
    }

    /// Clear stale calibrations from before cache-inclusive counting (v2.2),
    /// then move the legacy global calibration to the active account (one-time).
    /// Called once at launch. The per-account move only runs (and only marks
    /// itself done) when an active account exists — otherwise it retries on a
    /// later launch so a pre-login calibration isn't stranded on the global keys.
    static func migrateIfNeeded(
        activeAccountId: String? = AccountStore.persistedActiveAccountId,
        defaults: UserDefaults = .standard
    ) {
        let stored = defaults.integer(forKey: calibrationVersionKey)
        if stored < currentCalibrationVersion {
            defaults.removeObject(forKey: fiveHourLimitKeyBase)
            defaults.removeObject(forKey: sevenDayLimitKeyBase)
            defaults.removeObject(forKey: calibratedAtKeyBase)
            defaults.set(currentCalibrationVersion, forKey: calibrationVersionKey)
        }

        guard let accountId = activeAccountId, !defaults.bool(forKey: perAccountMigratedKey) else { return }
        for base in [fiveHourLimitKeyBase, sevenDayLimitKeyBase, calibratedAtKeyBase] {
            if let legacy = defaults.object(forKey: base) {
                defaults.set(legacy, forKey: scopedKey(base, accountId))
                defaults.removeObject(forKey: base)
            }
        }
        defaults.set(true, forKey: perAccountMigratedKey)
    }

    /// Calibrated 5-hour token limit for an account (0 = uncalibrated).
    /// UserDefaults is thread-safe — reads are nonisolated for use from views/snapshots.
    nonisolated static func fiveHourLimit(for accountId: String? = AccountStore.persistedActiveAccountId) -> Int {
        UserDefaults.standard.integer(forKey: scopedKey(fiveHourLimitKeyBase, accountId))
    }

    nonisolated static func setFiveHourLimit(_ value: Int, for accountId: String? = AccountStore.persistedActiveAccountId) {
        UserDefaults.standard.set(value, forKey: scopedKey(fiveHourLimitKeyBase, accountId))
    }

    /// Calibrated 7-day token limit for an account (0 = uncalibrated).
    nonisolated static func sevenDayLimit(for accountId: String? = AccountStore.persistedActiveAccountId) -> Int {
        UserDefaults.standard.integer(forKey: scopedKey(sevenDayLimitKeyBase, accountId))
    }

    nonisolated static func setSevenDayLimit(_ value: Int, for accountId: String? = AccountStore.persistedActiveAccountId) {
        UserDefaults.standard.set(value, forKey: scopedKey(sevenDayLimitKeyBase, accountId))
    }

    /// When the account's limits were last calibrated.
    nonisolated static func calibratedAt(for accountId: String? = AccountStore.persistedActiveAccountId) -> Date? {
        let ts = UserDefaults.standard.double(forKey: scopedKey(calibratedAtKeyBase, accountId))
        return ts > 0 ? Date(timeIntervalSinceReferenceDate: ts) : nil
    }

    nonisolated private static func markCalibrated(for accountId: String?) {
        UserDefaults.standard.set(
            Date().timeIntervalSinceReferenceDate,
            forKey: scopedKey(calibratedAtKeyBase, accountId)
        )
    }

    /// Whether the account has calibrated limits (from API or 429 event).
    nonisolated static func isCalibrated(for accountId: String? = AccountStore.persistedActiveAccountId) -> Bool {
        fiveHourLimit(for: accountId) > 0 || sevenDayLimit(for: accountId) > 0
    }

    /// Effective 5-hour limit: calibrated > plan-based > nil.
    /// The plan fallback resolves the account's own tier (API-reported
    /// `billingType` first, then the user-selected global tier).
    nonisolated static func effectiveFiveHourLimit(for accountId: String? = AccountStore.persistedActiveAccountId) -> Int? {
        let calibrated = fiveHourLimit(for: accountId)
        if calibrated > 0 {
            return calibrated
        }
        return PlanTier.effective(forAccountId: accountId)?.estimatedFiveHourLimit
    }

    /// Effective 7-day limit: calibrated > plan-based > nil.
    nonisolated static func effectiveSevenDayLimit(for accountId: String? = AccountStore.persistedActiveAccountId) -> Int? {
        let calibrated = sevenDayLimit(for: accountId)
        if calibrated > 0 {
            return calibrated
        }
        return PlanTier.effective(forAccountId: accountId)?.estimatedSevenDayLimit
    }

    /// Whether the active limit comes from calibration (exact) vs plan estimate (approximate).
    nonisolated static func limitSource(
        for window: MetricMode,
        accountId: String? = AccountStore.persistedActiveAccountId
    ) -> LimitSource? {
        switch window {
        case .fiveHour:
            if fiveHourLimit(for: accountId) > 0 {
                return .calibrated
            }
            if PlanTier.effective(forAccountId: accountId) != nil {
                return .planEstimate
            }
            return nil
        case .sevenDay:
            if sevenDayLimit(for: accountId) > 0 {
                return .calibrated
            }
            if PlanTier.effective(forAccountId: accountId) != nil {
                return .planEstimate
            }
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
    /// Only calibrates when utilization is inside `calibrationBand`. The edges are
    /// noisy: dividing by a small utilization magnifies measurement error (a 1%
    /// error at 5% utilization → ~20% error in the derived limit), which would let
    /// the local fallback read ≥100% when the API would report well under. A
    /// mid-range band (20–80%) keeps the derived limit stable.
    nonisolated static let calibrationBand: ClosedRange<Double> = 0.20...0.80

    static func calibrate(
        fiveHourUtilization: Double,
        sevenDayUtilization: Double,
        localFiveHourTokens: Int,
        localSevenDayTokens: Int,
        accountId: String? = AccountStore.persistedActiveAccountId
    ) {
        var updated = false
        if calibrationBand.contains(fiveHourUtilization), localFiveHourTokens > 0 {
            let derived = Int(Double(localFiveHourTokens) / fiveHourUtilization)
            // Sanity check: limit should be > 100K tokens
            if derived > 100_000 {
                setFiveHourLimit(derived, for: accountId)
                updated = true
            }
        }
        if calibrationBand.contains(sevenDayUtilization), localSevenDayTokens > 0 {
            let derived = Int(Double(localSevenDayTokens) / sevenDayUtilization)
            if derived > 100_000 {
                setSevenDayLimit(derived, for: accountId)
                updated = true
            }
        }
        if updated {
            markCalibrated(for: accountId)
        }
    }

    /// Estimate 5-hour utilization from local tokens (0–100, or nil if no limit known).
    nonisolated static func fiveHourPercent(
        tokens: Int,
        accountId: String? = AccountStore.persistedActiveAccountId
    ) -> Double? {
        guard let limit = effectiveFiveHourLimit(for: accountId), limit > 0 else { return nil }
        return min(Double(tokens) / Double(limit) * 100.0, 100.0)
    }

    /// Estimate 7-day utilization from local tokens (0–100, or nil if no limit known).
    nonisolated static func sevenDayPercent(
        tokens: Int,
        accountId: String? = AccountStore.persistedActiveAccountId
    ) -> Double? {
        guard let limit = effectiveSevenDayLimit(for: accountId), limit > 0 else { return nil }
        return min(Double(tokens) / Double(limit) * 100.0, 100.0)
    }

    // MARK: - Latest Token Counts (for 429 calibration)

    /// Updated each refresh cycle by UsageViewModel so 429 calibration can snapshot
    /// them. These reflect the ACTIVE account's aggregation — which is why
    /// `calibrateFrom429` refuses to seed any other account from them.
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
    ///
    /// Only seeds the ACTIVE account: `latest*Tokens` hold the active account's
    /// local counts, so a 429 on a fan-out fetch for another account carries no
    /// usable token signal for it.
    static func calibrateFrom429(
        accountId: String? = AccountStore.persistedActiveAccountId,
        activeAccountId: String? = AccountStore.persistedActiveAccountId
    ) {
        guard accountId == activeAccountId else {
            AppLogger.network.info("429 calibration skipped — non-active account \(accountId ?? "nil", privacy: .public)")
            return
        }
        let buffer = 0.95
        var updated = false
        if fiveHourLimit(for: accountId) == 0, latestFiveHourTokens > 100_000 {
            let derived = Int(Double(latestFiveHourTokens) / buffer)
            setFiveHourLimit(derived, for: accountId)
            updated = true
            AppLogger.network.info("429 seeded uncalibrated 5h limit: \(derived) tokens")
        }
        if sevenDayLimit(for: accountId) == 0, latestSevenDayTokens > 100_000 {
            let derived = Int(Double(latestSevenDayTokens) / buffer)
            setSevenDayLimit(derived, for: accountId)
            updated = true
            AppLogger.network.info("429 seeded uncalibrated 7d limit: \(derived) tokens")
        }
        if updated {
            markCalibrated(for: accountId)
        } else {
            AppLogger.network.info("429 calibration skipped — limits already set or local tokens too low")
        }
    }

    // MARK: - Manual Overrides

    /// Allow user to manually set their 5-hour token limit.
    static func setManualFiveHourLimit(_ limit: Int, for accountId: String? = AccountStore.persistedActiveAccountId) {
        setFiveHourLimit(max(limit, 0), for: accountId)
        markCalibrated(for: accountId)
    }

    /// Allow user to manually set their 7-day token limit.
    static func setManualSevenDayLimit(_ limit: Int, for accountId: String? = AccountStore.persistedActiveAccountId) {
        setSevenDayLimit(max(limit, 0), for: accountId)
        markCalibrated(for: accountId)
    }
}
