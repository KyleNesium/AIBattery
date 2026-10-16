import Foundation

/// Parsed from Anthropic's unified rate limit headers.
///
/// The API uses a unified sliding-window system with two windows:
///   - 5-hour window (short-term burst)
///   - 7-day window (long-term usage)
/// Each reports a utilization fraction (0.0–1.0) and a reset timestamp.
/// The `representative-claim` tells which window is the binding constraint.
struct RateLimitUsage: Equatable, Codable {
    /// Window identifiers used in API headers.
    static let fiveHourWindow = "five_hour"
    static let sevenDayWindow = "seven_day"

    /// Window durations — used to derive how far into a window the current reading is.
    static let fiveHourWindowDuration: TimeInterval = 5 * 3_600
    static let sevenDayWindowDuration: TimeInterval = 7 * 24 * 3_600

    /// Rollover-artifact guard thresholds. A window reading at/above
    /// `rolloverArtifactUtilizationThreshold` whose reset implies the window started
    /// less than `rolloverArtifactGracePeriod` ago is treated as a stale carry-over
    /// from the *previous* window (server-side rollover lag), not a genuine limit-hit —
    /// you cannot consume ~all of a multi-hour quota in the first few minutes.
    static let rolloverArtifactUtilizationThreshold = 0.95
    static let rolloverArtifactGracePeriod: TimeInterval = 600 // 10 minutes

    static func inferredWindowStatus(
        explicitStatus: String?,
        overallStatus: String,
        representativeClaim: String,
        window: String
    ) -> String {
        if let explicitStatus {
            return explicitStatus
        }
        guard overallStatus == "throttled" else { return overallStatus }
        return representativeClaim == window ? "throttled" : "allowed"
    }

    /// The binding constraint: "five_hour" or "seven_day"
    let representativeClaim: String

    /// 5-hour window
    let fiveHourUtilization: Double // 0.0 – 1.0
    let fiveHourReset: Date?
    let fiveHourStatus: String // "allowed" or "throttled"

    /// 7-day window
    let sevenDayUtilization: Double
    let sevenDayReset: Date?
    let sevenDayStatus: String

    /// Overall status
    let overallStatus: String // "allowed" or "throttled"

    /// Which provider produced this reading. Decodes as `.claude` for pre-v2.7
    /// persisted snapshots. Drives window labels only — thresholds and guards
    /// are provider-neutral.
    let provider: AIProvider

    /// Actual window durations from the provider payload (Codex sends them;
    /// Anthropic doesn't — nil means "assume 300 / 10080").
    let fiveHourWindowMinutes: Int?
    let sevenDayWindowMinutes: Int?

    /// Codex credit budget (Business / Enterprise plans): when set, both windows above
    /// mirror the budget's `usedPercent` / `resetsAt` so every percent path (menu bar,
    /// auto mode, notifications, spike filter) works unchanged, and the popover renders
    /// a single "Credits" bar instead of 5h/Weekly. nil for windowed plans and Claude.
    let creditBudget: CodexCreditBudget?

    /// True for a real spend-control budget (limit > 0) or an uncapped spend-control plan
    /// (no windows, no individual limit). A subscription plan that merely reports a
    /// purchased-credit balance keeps its windowed layout.
    var isCreditBudget: Bool {
        guard let creditBudget else { return false }
        return creditBudget.limit > 0 || creditBudget.isUncapped
    }

    /// Actual window lengths: from the payload when the provider sends them (Codex),
    /// else the 5-hour / 7-day defaults (spec §3: "defaulted to 300/10080 when absent").
    var fiveHourDuration: TimeInterval { TimeInterval(fiveHourWindowMinutes ?? 300) * 60 }
    var sevenDayDuration: TimeInterval { TimeInterval(sevenDayWindowMinutes ?? 10_080) * 60 }

    /// Purchased-credit balance on subscription plans, if reported.
    var creditBalance: Double? { creditBudget?.balance }

    init(
        representativeClaim: String,
        fiveHourUtilization: Double, fiveHourReset: Date?, fiveHourStatus: String,
        sevenDayUtilization: Double, sevenDayReset: Date?, sevenDayStatus: String,
        overallStatus: String,
        provider: AIProvider = .claude,
        fiveHourWindowMinutes: Int? = nil,
        sevenDayWindowMinutes: Int? = nil,
        creditBudget: CodexCreditBudget? = nil
    ) {
        self.representativeClaim = representativeClaim
        self.fiveHourUtilization = fiveHourUtilization
        self.fiveHourReset = fiveHourReset
        self.fiveHourStatus = fiveHourStatus
        self.sevenDayUtilization = sevenDayUtilization
        self.sevenDayReset = sevenDayReset
        self.sevenDayStatus = sevenDayStatus
        self.overallStatus = overallStatus
        self.provider = provider
        self.fiveHourWindowMinutes = fiveHourWindowMinutes
        self.sevenDayWindowMinutes = sevenDayWindowMinutes
        self.creditBudget = creditBudget
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        representativeClaim = try c.decode(String.self, forKey: .representativeClaim)
        fiveHourUtilization = try c.decode(Double.self, forKey: .fiveHourUtilization)
        fiveHourReset = try c.decodeIfPresent(Date.self, forKey: .fiveHourReset)
        fiveHourStatus = try c.decode(String.self, forKey: .fiveHourStatus)
        sevenDayUtilization = try c.decode(Double.self, forKey: .sevenDayUtilization)
        sevenDayReset = try c.decodeIfPresent(Date.self, forKey: .sevenDayReset)
        sevenDayStatus = try c.decode(String.self, forKey: .sevenDayStatus)
        overallStatus = try c.decode(String.self, forKey: .overallStatus)
        provider = try c.decodeIfPresent(AIProvider.self, forKey: .provider) ?? .claude
        fiveHourWindowMinutes = try c.decodeIfPresent(Int.self, forKey: .fiveHourWindowMinutes)
        sevenDayWindowMinutes = try c.decodeIfPresent(Int.self, forKey: .sevenDayWindowMinutes)
        creditBudget = try c.decodeIfPresent(CodexCreditBudget.self, forKey: .creditBudget)
    }

    // MARK: - Convenience

    /// Resolve a per-window value by the binding window (`representativeClaim`):
    /// the 7-day value when it is the binding constraint, the 5-hour value
    /// otherwise (matching the original switches' `default:` arm). Single home
    /// for the dispatch that was previously copy-pasted across six properties.
    private func bindingValue<T>(fiveHour: T, sevenDay: T) -> T {
        representativeClaim == Self.sevenDayWindow ? sevenDay : fiveHour
    }

    /// The utilization percentage of the binding window (0–100).
    var requestsPercentUsed: Double {
        bindingValue(fiveHour: fiveHourUtilization, sevenDay: sevenDayUtilization) * 100.0
    }

    /// 5-hour utilization as percentage (0–100).
    var fiveHourPercent: Double { fiveHourUtilization * 100.0 }

    /// 7-day utilization as percentage (0–100).
    var sevenDayPercent: Double { sevenDayUtilization * 100.0 }

    /// Reset date of the binding window.
    var bindingReset: Date? {
        bindingValue(fiveHour: fiveHourReset, sevenDay: sevenDayReset)
    }

    /// "7-Day" for Claude, "Weekly" for Codex — same 7-day window, provider vocabulary.
    /// "Credits" when the reading is a Codex credit budget.
    var sevenDayDisplayLabel: String { isCreditBudget ? "Credits" : provider.secondaryWindowLabel }

    /// Human-readable label for the binding window.
    var bindingWindowLabel: String {
        if isCreditBudget {
            return "Credits"
        }
        return bindingValue(fiveHour: "5-hour", sevenDay: provider == .codex ? "Weekly" : "7-day")
    }

    /// Compact code for the binding window, for the menu bar: "5H", "7D"/"WK", or "CR".
    /// Lets a throttled countdown say which window you're waiting on (hours vs a day+).
    var bindingWindowShortCode: String {
        if isCreditBudget {
            return "CR"
        }
        return bindingValue(fiveHour: "5H", sevenDay: provider.secondaryWindowShortCode)
    }

    /// Whether the user is currently throttled.
    /// Checks overall status and per-window statuses — the API may report
    /// a window as "throttled" before the overall status reflects it.
    var isThrottled: Bool {
        overallStatus == "throttled"
            || fiveHourStatus == "throttled"
            || sevenDayStatus == "throttled"
    }

    /// Whether a specific window is currently throttled.
    /// A global throttled status alone is not enough to mark every window as throttled.
    func isWindowThrottled(_ window: String) -> Bool {
        switch window {
        case Self.sevenDayWindow:
            sevenDayStatus == "throttled"
        default:
            fiveHourStatus == "throttled"
        }
    }

    /// Force a throttled state when the HTTP response proves the account is rate limited
    /// but the unified headers lag behind and still report an allowed status/utilization.
    func markedThrottled(bindingWindow: String? = nil) -> RateLimitUsage {
        let window = bindingWindow ?? representativeClaim
        return RateLimitUsage(
            representativeClaim: representativeClaim,
            fiveHourUtilization: fiveHourUtilization,
            fiveHourReset: fiveHourReset,
            fiveHourStatus: window == Self.fiveHourWindow ? "throttled" : fiveHourStatus,
            sevenDayUtilization: sevenDayUtilization,
            sevenDayReset: sevenDayReset,
            sevenDayStatus: window == Self.sevenDayWindow ? "throttled" : sevenDayStatus,
            overallStatus: "throttled",
            provider: provider,
            fiveHourWindowMinutes: fiveHourWindowMinutes,
            sevenDayWindowMinutes: sevenDayWindowMinutes,
            creditBudget: creditBudget
        )
    }

    /// Return a copy normalizing two kinds of stale state. Used on the cache /
    /// stale-fallback paths (cache restore, runtime cache hit, snapshot stale
    /// fallback) — never on fresh data.
    ///
    /// 1. **Expired window** (reset in the past): utilization → 0, reset → nil,
    ///    status → "allowed". The window has rolled over; showing the old value
    ///    would mislead until the first fresh fetch lands.
    /// 2. **Unbounded throttle** (status "throttled" with *no* reset): a genuine
    ///    quota throttle always carries a reset, so a reset-less throttle can never
    ///    be aged out by (1) and would stick forever on the stale path. Drop the
    ///    throttle flag (status → "allowed") while keeping the last-known
    ///    utilization, so the bar stops claiming "Throttled" but still reflects
    ///    how full the window was. A fresh fetch re-establishes the truth.
    func withClearedExpiredWindows(now: Date = .now) -> RateLimitUsage {
        let fiveHourExpired = (fiveHourReset.map { $0 <= now } ?? false)
        let sevenDayExpired = (sevenDayReset.map { $0 <= now } ?? false)
        let fiveHourUnboundedThrottle = (fiveHourReset == nil && fiveHourStatus == "throttled")
        let sevenDayUnboundedThrottle = (sevenDayReset == nil && sevenDayStatus == "throttled")
        // A credit budget is projected onto both windows, but the Credits bar reads the
        // nested object directly — roll it over with them, or the popover keeps the old
        // period's "Budget reached" while the menu bar already shows 0%.
        let budgetExpired = creditBudget?.resetsAt.map { $0 <= now } ?? false

        guard fiveHourExpired || sevenDayExpired || budgetExpired
            || fiveHourUnboundedThrottle || sevenDayUnboundedThrottle else { return self }

        let bindingCleared = bindingValue(
            fiveHour: fiveHourExpired || fiveHourUnboundedThrottle,
            sevenDay: sevenDayExpired || sevenDayUnboundedThrottle
        )

        return RateLimitUsage(
            representativeClaim: representativeClaim,
            fiveHourUtilization: fiveHourExpired ? 0 : fiveHourUtilization,
            fiveHourReset: fiveHourExpired ? nil : fiveHourReset,
            fiveHourStatus: (fiveHourExpired || fiveHourUnboundedThrottle) ? "allowed" : fiveHourStatus,
            sevenDayUtilization: sevenDayExpired ? 0 : sevenDayUtilization,
            sevenDayReset: sevenDayExpired ? nil : sevenDayReset,
            sevenDayStatus: (sevenDayExpired || sevenDayUnboundedThrottle) ? "allowed" : sevenDayStatus,
            overallStatus: bindingCleared ? "allowed" : overallStatus,
            provider: provider,
            fiveHourWindowMinutes: fiveHourWindowMinutes,
            sevenDayWindowMinutes: sevenDayWindowMinutes,
            creditBudget: budgetExpired ? creditBudget?.rolledOver() : creditBudget
        )
    }

    /// Whether a window reading is a rollover artifact: near-full utilization on a
    /// window whose reset says it only just started. Such a reading is the previous
    /// window's usage lingering on a fresh window (server-side eventual consistency at
    /// the reset boundary) and must not be shown as "Limit reached".
    private static func isRolloverArtifact(
        utilization: Double,
        reset: Date?,
        windowDuration: TimeInterval,
        now: Date
    ) -> Bool {
        guard utilization >= rolloverArtifactUtilizationThreshold, let reset else { return false }
        let timeUntilReset = reset.timeIntervalSince(now)
        // A past/at reset is the expired-window case (handled by withClearedExpiredWindows).
        guard timeUntilReset > 0 else { return false }
        let elapsed = windowDuration - timeUntilReset
        // A reset further away than the window is long is not "a window that just
        // started" — it's a period this filter knows nothing about (e.g. a monthly
        // credit budget). Never clear those.
        guard elapsed >= 0 else { return false }
        return elapsed < rolloverArtifactGracePeriod
    }

    /// Return a copy that suppresses rollover artifacts — near-full utilization on a
    /// window that just rolled over. Unlike `withClearedExpiredWindows`, the reset is
    /// the *valid* new-window reset, so it's preserved (the countdown keeps running);
    /// only the stale utilization/status is cleared. Used on the displayed rate-limit
    /// data so a window that reset moments ago doesn't read "100% / Limit reached"
    /// until the next poll catches up.
    func withClearedRolloverArtifacts(now: Date = .now) -> RateLimitUsage {
        // A credit budget mirrors one period-based number onto both windows; the 5h/7d
        // rollover heuristic does not apply to it (see isRolloverArtifact).
        guard !isCreditBudget else { return self }
        let fiveHourArtifact = Self.isRolloverArtifact(
            utilization: fiveHourUtilization, reset: fiveHourReset,
            windowDuration: fiveHourDuration, now: now
        )
        let sevenDayArtifact = Self.isRolloverArtifact(
            utilization: sevenDayUtilization, reset: sevenDayReset,
            windowDuration: sevenDayDuration, now: now
        )

        guard fiveHourArtifact || sevenDayArtifact else { return self }

        let bindingCleared = bindingValue(fiveHour: fiveHourArtifact, sevenDay: sevenDayArtifact)

        return RateLimitUsage(
            representativeClaim: representativeClaim,
            fiveHourUtilization: fiveHourArtifact ? 0 : fiveHourUtilization,
            fiveHourReset: fiveHourReset,
            fiveHourStatus: fiveHourArtifact ? "allowed" : fiveHourStatus,
            sevenDayUtilization: sevenDayArtifact ? 0 : sevenDayUtilization,
            sevenDayReset: sevenDayReset,
            sevenDayStatus: sevenDayArtifact ? "allowed" : sevenDayStatus,
            overallStatus: bindingCleared ? "allowed" : overallStatus,
            provider: provider,
            fiveHourWindowMinutes: fiveHourWindowMinutes,
            sevenDayWindowMinutes: sevenDayWindowMinutes,
            creditBudget: creditBudget
        )
    }

    // MARK: - Countdown formatter

    /// Compact countdown string for menu bar: "2h 15m", "45m", "0s"
    static func countdownText(to date: Date, from now: Date = .now) -> String {
        DurationFormatter.compact(date.timeIntervalSince(now))
    }

    // MARK: - Predictive estimate

    /// Estimate time until the rate limit is reached for a given window,
    /// based on current utilization and time remaining until reset.
    /// Returns nil if utilization is too low or the estimate exceeds reset time.
    func estimatedTimeToLimit(for window: String) -> TimeInterval? {
        estimatedTimeToLimit(for: window, now: .now)
    }

    /// Injected-clock overload for pure callers (`AccountCard.state`) and tests.
    func estimatedTimeToLimit(for window: String, now: Date) -> TimeInterval? {
        let (utilization, reset): (Double, Date?) = switch window {
        case Self.sevenDayWindow: (sevenDayUtilization, sevenDayReset)
        default: (fiveHourUtilization, fiveHourReset)
        }

        guard utilization > 0.20, let reset else { return nil }

        let remaining = reset.timeIntervalSince(now)
        guard remaining > 0 else { return nil }

        // Window duration from the payload when present, else the provider default
        let windowDuration: TimeInterval = window == Self.sevenDayWindow ? sevenDayDuration : fiveHourDuration
        let elapsed = windowDuration - remaining

        guard elapsed > 60 else { return nil } // Need meaningful elapsed time

        // burn rate = utilization / elapsed, project when we reach 1.0
        let rate = utilization / elapsed
        let timeToFull = (1.0 - utilization) / rate

        // Only show if estimate is before the reset (otherwise it's fine)
        guard timeToFull < remaining else { return nil }

        return timeToFull
    }
}
