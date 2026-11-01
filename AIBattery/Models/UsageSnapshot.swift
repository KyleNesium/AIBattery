import Foundation

struct UsageSnapshot: Equatable {
    /// Custom equality skips `lastUpdated` (always changes) and compares meaningful data.
    /// Prevents unnecessary SwiftUI diffs when polling returns identical data.
    static func == (lhs: UsageSnapshot, rhs: UsageSnapshot) -> Bool {
        lhs.rateLimits == rhs.rateLimits
            && lhs.rateLimitSource == rhs.rateLimitSource
            && lhs.standardLimits == rhs.standardLimits
            && lhs.rateLimitsFresh == rhs.rateLimitsFresh
            && lhs.totalSessions == rhs.totalSessions
            && lhs.totalMessages == rhs.totalMessages
            && lhs.todayMessages == rhs.todayMessages
            && lhs.todaySessions == rhs.todaySessions
            && lhs.todayToolCalls == rhs.todayToolCalls
            && lhs.totalTokens == rhs.totalTokens
            && lhs.totalUsageTokens == rhs.totalUsageTokens
            && lhs.totalProjectTokens == rhs.totalProjectTokens
            && lhs.totalProjectUsageTokens == rhs.totalProjectUsageTokens
            && lhs.totalProjectCost == rhs.totalProjectCost
            && lhs.modelTokens == rhs.modelTokens
            && lhs.projectTokens == rhs.projectTokens
            && lhs.dailyActivity == rhs.dailyActivity
            && lhs.topSessionHealths == rhs.topSessionHealths
            && lhs.tokenHealth == rhs.tokenHealth
            && lhs.hourCounts == rhs.hourCounts
            && lhs.todayHourCounts == rhs.todayHourCounts
            && lhs.peakHour == rhs.peakHour
            && lhs.peakHourCount == rhs.peakHourCount
            && lhs.longestSessionDuration == rhs.longestSessionDuration
            && lhs.longestSessionMessages == rhs.longestSessionMessages
            && lhs.firstSessionDate == rhs.firstSessionDate
            && lhs.ledgerSince == rhs.ledgerSince
            && lhs.fiveHourTokens == rhs.fiveHourTokens
            && lhs.sevenDayTokens == rhs.sevenDayTokens
            && lhs.fiveHourTokenBuckets == rhs.fiveHourTokenBuckets
            && lhs.dailyTokenTotals == rhs.dailyTokenTotals
            && lhs.sevenDayTokenBuckets == rhs.sevenDayTokenBuckets
            && lhs.todayModelTokens == rhs.todayModelTokens
            && lhs.weekModelTokens == rhs.weekModelTokens
            && lhs.monthModelTokens == rhs.monthModelTokens
            // busiestDayOfWeek is a tuple — compare components manually
            && lhs.busiestDayOfWeek?.name == rhs.busiestDayOfWeek?.name
            && lhs.busiestDayOfWeek?.averageCount == rhs.busiestDayOfWeek?.averageCount
            && lhs.provider == rhs.provider
            && lhs.costIsBilled == rhs.costIsBilled
            && lhs.unattributedTurnCount == rhs.unattributedTurnCount
    }

    /// Weekday symbols from the user's current calendar (Sunday = index 0).
    private static let weekdaySymbols = Calendar.current.weekdaySymbols

    let lastUpdated: Date

    // Rate limit usage (from unified API response headers)
    let rateLimits: RateLimitUsage?
    let rateLimitSource: RateLimitSource?
    /// Standard per-minute API rate limits (fallback when unified 5h/7d unavailable).
    let standardLimits: StandardRateLimits?
    /// Whether the rate-limit *values* came from a genuinely fresh fetch this cycle (unified
    /// headers AND not cache-served). When `false`, the data is held/stale — the bars still
    /// show the real (held) API percentage, but the alarm is suppressed per window via
    /// `rateLimitPercentConfirmed(for:)` unless that window is itself throttled. Gates only
    /// the alarm; never the displayed number.
    let rateLimitsFresh: Bool

    // From stats-cache.json
    let firstSessionDate: Date?
    /// Codex only: when `TokenLedger` first recorded this account's series — the ledger
    /// has no lifetime cache of its own, so this dates the All-Time figure. Nil for
    /// Claude (stats-cache dates it instead) and until the first merge completes.
    /// Declared with a default so the memberwise init stays source-compatible.
    var ledgerSince: Date? = nil
    let totalSessions: Int
    let totalMessages: Int
    let longestSessionDuration: String?
    let longestSessionMessages: Int
    let peakHour: Int?
    let peakHourCount: Int

    // Today's activity
    let todayMessages: Int
    let todaySessions: Int
    let todayToolCalls: Int

    // Token breakdown per model
    let modelTokens: [ModelTokenSummary]

    // Token breakdown per project (from JSONL cwd field)
    let projectTokens: [ProjectTokenSummary]

    // Total tokens (pre-computed at construction to avoid per-render reduce)
    let totalTokens: Int
    /// Input + output only — excludes cache tokens for meaningful usage display.
    let totalUsageTokens: Int

    // Total project tokens (pre-computed at construction to avoid per-render reduce)
    let totalProjectTokens: Int
    /// Input + output only — excludes cache tokens for meaningful usage display.
    let totalProjectUsageTokens: Int
    let totalProjectCost: Double

    // Local token totals for 5h/7d usage estimation (sum of input+output across all models)
    let fiveHourTokens: Int
    let sevenDayTokens: Int
    /// 5-hour 15-minute token buckets for the chart (bucket 0 = oldest, 19 = now).
    let fiveHourTokenBuckets: [Int: Int]
    /// Per-date token totals for 7D and 12M chart modes (date-key → all token types).
    let dailyTokenTotals: [String: Int]
    /// 7-day hourly token buckets (bucket 0 = oldest, 167 = the current hour).
    ///
    /// `dailyTokenTotals` is day-granular, so a 7-day window that starts mid-day could
    /// only ever be approximated by counting its first calendar day whole — up to 24 h
    /// of pre-window tokens. These buckets are the same accumulation at hour resolution,
    /// so the window can start where the provider says it starts. Declared with a
    /// default so the memberwise init stays source-compatible; empty falls back to the
    /// day-keyed sum.
    var sevenDayTokenBuckets: [Int: Int] = [:]

    // Windowed model tokens for Insights cost breakdown (JSONL-only, not ledger-merged)
    let todayModelTokens: [ModelTokenSummary]
    let weekModelTokens: [ModelTokenSummary]
    let monthModelTokens: [ModelTokenSummary]

    /// The percentage for a given metric mode — shared by menu bar and popover.
    /// Falls back to local token estimates when API rate limit data is unavailable.
    /// Context health uses the highest usage across all tracked sessions (not just
    /// the most recent), so auto mode and the menu bar reflect the most critical session.
    /// The displayed percentage is always the **real API utilization** when we have rate
    /// limits — fresh, or the last-known held value (a header-less-but-successful fetch is
    /// not a connection error, so the held real value shows; the `refresh()` spike filter
    /// already holds a fresh-but-wrong near-full reading at the *previous real value*, so a
    /// false high never reaches here). `LocalUsageEstimate` is used only when there is **no
    /// API data at all** (standard-API-key users) — it is never substituted for a held API
    /// reading, because a token-derived guess doesn't make sense once the API has spoken.
    func percent(for mode: MetricMode) -> Double {
        switch mode {
        case .fiveHour:
            rateLimits?.fiveHourPercent
                ?? (provider == .claude ? LocalUsageEstimate.fiveHourPercent(tokens: fiveHourTokens) : standardLimits?.peakPercent)
                ?? 0
        case .sevenDay:
            rateLimits?.sevenDayPercent
                ?? (provider == .claude ? LocalUsageEstimate.sevenDayPercent(tokens: sevenDayTokens) : standardLimits?.peakPercent)
                ?? 0
        case .contextHealth:
            topSessionHealths.first?.usagePercentage
                ?? tokenHealth?.usagePercentage
                ?? 0
        }
    }

    /// Whether a given window's *alarm* (the red "Limit reached" / broken star) may fire.
    /// Confirmed when the data is fresh this cycle OR *this window* is genuinely throttled
    /// (authoritative, carries a reset, self-expires). Scoped per window so a throttle on
    /// one window can't confirm a stale near-full reading on the other. Gates only the
    /// alarm — the displayed percentage is always the real API value (see `percent(for:)`).
    func rateLimitPercentConfirmed(for window: String) -> Bool {
        rateLimitsFresh || (rateLimits?.isWindowThrottled(window) ?? false)
    }

    /// Token total for the 5-hour rate limit window, aligned to the actual window boundary.
    /// Uses the reset time to determine when the current window started, then sums only
    /// the 15-minute buckets within that window. Falls back to the full trailing sum.
    func fiveHourWindowTokens(resetsAt: Date?) -> Int {
        guard let resetsAt else { return fiveHourTokens }
        let remaining = resetsAt.timeIntervalSinceNow
        guard remaining > 0 else { return fiveHourTokens }
        let start = Self.firstInWindowBucket(remaining: remaining, bucketCount: 20, bucketDuration: 900)
        return (start..<20).reduce(0) { $0 + (fiveHourTokenBuckets[$1] ?? 0) }
    }

    /// Token total for the 7-day rate limit window, aligned to the actual window boundary.
    /// Sums the hourly buckets from the window start; falls back to the day-keyed totals
    /// when a snapshot carries no buckets (which over-counts the first day — see
    /// `sevenDayTokenBuckets`).
    func sevenDayWindowTokens(resetsAt: Date?) -> Int {
        guard let resetsAt else { return sevenDayTokens }
        let remaining = resetsAt.timeIntervalSinceNow
        guard remaining > 0 else { return sevenDayTokens }
        guard !sevenDayTokenBuckets.isEmpty else {
            let elapsed = 7 * 24 * 3_600.0 - remaining
            guard elapsed > 0 else { return 0 }
            let windowStartKey = DateFormatters.dateKey.string(from: Date().addingTimeInterval(-elapsed))
            return dailyTokenTotals.reduce(0) { total, entry in
                entry.key >= windowStartKey ? total + entry.value : total
            }
        }
        let count = Self.sevenDayBucketCount
        let start = Self.firstInWindowBucket(
            remaining: remaining, bucketCount: count, bucketDuration: Self.sevenDayBucketDuration
        )
        return (start..<count).reduce(0) { $0 + (sevenDayTokenBuckets[$1] ?? 0) }
    }

    /// Hourly buckets spanning the 7-day window.
    static let sevenDayBucketCount = 7 * 24
    static let sevenDayBucketDuration: TimeInterval = 3_600

    /// Index of the first bucket that lies **entirely** inside the window, given how
    /// much of the window is left.
    ///
    /// Buckets run oldest-first and the last one is "now". The bucket the window
    /// started inside straddles the boundary, so counting it added up to one bucket of
    /// pre-window tokens to the figure under the bar — 15 minutes on the 5-hour window,
    /// and a whole calendar day on the 7-day one before it had buckets of its own.
    /// Rounding the remaining time up excludes that partial bucket instead.
    static func firstInWindowBucket(
        remaining: TimeInterval,
        bucketCount: Int,
        bucketDuration: TimeInterval
    ) -> Int {
        max(0, min(bucketCount, Int(ceil(remaining / bucketDuration))))
    }

    /// Whether the 5h/7d data comes from local token estimation (no API data).
    /// Claude only — the calibration / plan-tier machinery is Anthropic-specific and a
    /// Codex account must never fall back to it.
    var isUsingLocalEstimate: Bool {
        provider == .claude && rateLimits == nil && (fiveHourTokens > 0 || sevenDayTokens > 0)
    }

    /// De-escalation requires the metric to drop this many percentage points below its
    /// escalation threshold before releasing the held mode.
    static let hysteresisDeescalationBand = 10.0

    /// Rate limit percentage at or above which Tier 2 (rate limit escalation) kicks in.
    static let rateLimitEscalationThreshold = 80.0

    /// Context health percentage at or above which Tier 3 (context escalation) kicks in.
    static let contextEscalationThreshold = 60.0

    /// Maximum age (in seconds) for a session to be considered active.
    /// Sessions with no activity within this window are excluded from context health.
    static let sessionStalenessInterval: TimeInterval = 30 * 60 // 30 minutes

    /// Whether any tracked session has been active within the staleness window.
    var hasActiveSession: Bool {
        let cutoff = Date().addingTimeInterval(-Self.sessionStalenessInterval)
        return topSessionHealths.contains { health in
            guard let activity = health.lastActivity else { return false }
            return activity > cutoff
        }
    }

    /// Auto mode: four-tier deterministic escalation ladder.
    /// Throttle → rate limit >=80% → active context >=60% → binding rate limit.
    var autoResolvedMode: MetricMode {
        // Tier 1: Throttled — hard constraint, tokens are prerequisite for any work
        if let rl = rateLimits, rl.isThrottled {
            return rl.representativeClaim == RateLimitUsage.sevenDayWindow
                ? .sevenDay : .fiveHour
        }

        // Tier 2: Rate limit >=80% — capacity pressure takes priority
        let fiveHour = percent(for: .fiveHour)
        let sevenDay = percent(for: .sevenDay)
        let maxRate = max(fiveHour, sevenDay)
        if maxRate >= Self.rateLimitEscalationThreshold {
            return sevenDay >= fiveHour ? .sevenDay : .fiveHour
        }

        // Tier 3: Active context >=60% — only when a session is actively in use
        if hasActiveSession, percent(for: .contextHealth) >= Self.contextEscalationThreshold {
            return .contextHealth
        }

        // Tier 4: Default — show binding (highest-consumed) rate limit window
        if let rl = rateLimits {
            return rl.representativeClaim == RateLimitUsage.sevenDayWindow
                ? .sevenDay : .fiveHour
        }
        // No API data — use local estimates to pick the higher-consumed window
        return sevenDay >= fiveHour && sevenDay > 0 ? .sevenDay : .fiveHour
    }

    /// Apply hysteresis: if the previous mode still qualifies within its de-escalation band,
    /// keep it. Upward escalation and throttle bypass hysteresis entirely.
    /// - Parameters:
    ///   - candidate: The mode that `autoResolvedMode` selected this poll
    ///   - previous: The mode that was displayed last poll (nil on first poll or after reset)
    ///   - snapshot: Current snapshot for reading percentage values
    /// - Returns: The mode to display (may be `previous` if hysteresis holds)
    static func applyHysteresis(candidate: MetricMode, previous: MetricMode?, snapshot: UsageSnapshot) -> MetricMode {
        // No previous state — first poll or after reset
        guard let previous else { return candidate }

        // Throttle always wins immediately (Tier 1 bypass)
        if let rl = snapshot.rateLimits, rl.isThrottled {
            return candidate
        }

        // If candidate equals previous, no change needed
        if candidate == previous {
            return candidate
        }

        // Check if previous mode still qualifies within its de-escalation band
        switch previous {
        case .fiveHour, .sevenDay:
            // Previous was a rate limit mode — hold if RL still above release threshold
            let releaseThreshold = rateLimitEscalationThreshold - hysteresisDeescalationBand
            let currentPercent = snapshot.percent(for: previous)
            if currentPercent >= releaseThreshold {
                return previous
            }
        case .contextHealth:
            // Previous was context escalation — hold if context above release AND session active
            let releaseThreshold = contextEscalationThreshold - hysteresisDeescalationBand
            let currentPercent = snapshot.percent(for: .contextHealth)
            if snapshot.hasActiveSession, currentPercent >= releaseThreshold {
                return previous
            }
        }

        // Previous mode's metric dropped below release threshold, or upward escalation
        return candidate
    }

    // Daily activity for chart
    let dailyActivity: [DailyActivity]

    // MARK: - Projections & trends

    // `dailyAverage` and `trendDirection` used to live here. Both were computed on every
    // aggregation cycle, reached no view, and were index-based — so they would have been
    // wrong on sparse history had anything ever shown them. The trend the Insights row
    // does show is `ActivityTrendComputation`, which works off `dailyTokenTotals`.

    /// Busiest day of the week based on daily activity history.
    /// Pre-computed at construction to avoid iterating all dailyActivity on every view render.
    let busiestDayOfWeek: (name: String, averageCount: Int)?

    /// The weekday with the highest average message count, or nil when there is nothing
    /// to average. Pre-computed at construction so no view iterates `dailyActivity`.
    ///
    /// This used to also produce a daily average and a week-over-week trend; both reached
    /// no view and were index-based rather than date-based, so they would have been wrong
    /// on sparse history. The trend the Insights row shows is `ActivityTrendComputation`.
    static func computeBusiestDay(_ dailyActivity: [DailyActivity]) -> (name: String, averageCount: Int)? {
        guard !dailyActivity.isEmpty else { return nil }

        let calendar = Calendar.current
        var weekdayTotals = [Int: Int]()
        var weekdayCounts = [Int: Int]()

        for day in dailyActivity {
            guard let date = day.parsedDate else { continue }
            let weekday = calendar.component(.weekday, from: date)
            weekdayTotals[weekday, default: 0] += day.messageCount
            weekdayCounts[weekday, default: 0] += 1
        }

        guard let (weekday, total) = weekdayTotals.max(by: { a, b in
            let avgA = Double(a.value) / Double(weekdayCounts[a.key] ?? 1)
            let avgB = Double(b.value) / Double(weekdayCounts[b.key] ?? 1)
            // Equal averages break on the weekday index, so the answer is stable between
            // polls instead of following dictionary order.
            return avgA == avgB ? a.key > b.key : avgA < avgB
        }) else { return nil }

        let average = total / max(weekdayCounts[weekday] ?? 1, 1)
        let index = weekday - 1
        guard average > 0, index >= 0, index < weekdaySymbols.count else { return nil }
        return (weekdaySymbols[index], average)
    }

    let hourCounts: [String: Int]

    // Trailing 24-hour breakdown (hour "0"-"23" → count, from JSONL only)
    let todayHourCounts: [String: Int]

    // Token health for the most recent session (last JSONL entry's session)
    let tokenHealth: TokenHealthStatus?

    // Top sessions sorted by highest context usage (up to 5, within last 24h)
    let topSessionHealths: [TokenHealthStatus]

    /// Which provider's local data built this snapshot. Views use it for labels
    /// ("7-Day" vs "Weekly"), footer links, and the Insights data-source caveat.
    /// Declared last with a default so the memberwise init stays source-compatible.
    var provider: AIProvider = .claude

    /// True for pay-per-token accounts (Codex API key): the cost figures are an actual
    /// bill at API rates, not the subscription "API-equivalent" framing.
    var costIsBilled: Bool = false

    /// Turns hidden from this snapshot because their rollout carries no account stamp
    /// (older Codex CLI versions) while per-account attribution is active. 0 otherwise.
    var unattributedTurnCount: Int = 0
}

struct ModelTokenSummary: Identifiable, Equatable {
    let id: String // model ID
    let displayName: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int
    /// Pre-computed API-equivalent cost (avoids per-render pricing lock acquisition).
    let estimatedCost: Double

    /// Thinking / reasoning tokens — a subset of `outputTokens` (never added to totals).
    var reasoningTokens: Int = 0

    /// Share of output spent on thinking / reasoning (0…1); nil when there is no output.
    var reasoningShare: Double? {
        guard outputTokens > 0 else { return nil }
        return min(Double(reasoningTokens) / Double(outputTokens), 1)
    }

    var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens
    }

    /// Input + output only — actual consumption excluding cache.
    var usageTokens: Int {
        inputTokens + outputTokens
    }

    /// Cache hit rate as percentage (0–100). Returns nil when there are no input or cache tokens.
    var cacheHitRate: Double? {
        let denominator = cacheReadTokens + inputTokens
        guard denominator > 0 else { return nil }
        return Double(cacheReadTokens) / Double(denominator) * 100
    }
}
