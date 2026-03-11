import Foundation

struct UsageSnapshot {
    /// Weekday symbols from the user's current calendar (Sunday = index 0).
    private static let weekdaySymbols = Calendar.current.weekdaySymbols

    let lastUpdated: Date

    // Rate limit usage (from unified API response headers)
    let rateLimits: RateLimitUsage?

    // From stats-cache.json
    let firstSessionDate: Date?
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

    // Total tokens (pre-computed at construction to avoid per-render reduce)
    let totalTokens: Int

    /// The percentage for a given metric mode — shared by menu bar and popover.
    /// Context health uses the highest usage across all tracked sessions (not just
    /// the most recent), so auto mode and the menu bar reflect the most critical session.
    func percent(for mode: MetricMode) -> Double {
        switch mode {
        case .fiveHour: return rateLimits?.fiveHourPercent ?? 0
        case .sevenDay: return rateLimits?.sevenDayPercent ?? 0
        case .contextHealth:
            return topSessionHealths.first?.usagePercentage
                ?? tokenHealth?.usagePercentage
                ?? 0
        }
    }

    /// Rate limit percentage at or above which Tier 2 (near-exhaustion) kicks in.
    /// At this level, rate limits always take priority over context health.
    static let nearExhaustionThreshold = 95.0

    /// Auto mode: three-tier priority — throttling > near-exhaustion > urgency-normalized.
    /// Rate limit exhaustion is a harder constraint than context health (no tokens = no work),
    /// so it unconditionally supersedes context health at ≥95%.
    var autoResolvedMode: MetricMode {
        // Tier 1: Throttled — hard constraint, tokens are prerequisite for any work
        if let rl = rateLimits, rl.isThrottled {
            return rl.representativeClaim == RateLimitUsage.sevenDayWindow
                ? .sevenDay : .fiveHour
        }

        let fiveHour = percent(for: .fiveHour)
        let sevenDay = percent(for: .sevenDay)

        // Tier 2: Near-exhaustion — rate limits ≥95% always beat everything
        let maxRate = max(fiveHour, sevenDay)
        if maxRate >= Self.nearExhaustionThreshold {
            return sevenDay >= fiveHour ? .sevenDay : .fiveHour
        }

        // Tier 3: Urgency-normalized — each mode's thresholds map to a shared 0–1 scale.
        // Rate limit modes get a time-proximity boost when estimated time to limit is short:
        // a window hitting its cap in minutes is more urgent than one with hours left.
        // Ties broken by actionability: context > 5h > 7d.
        let scored: [(MetricMode, Double)] = MetricMode.allCases.map { mode in
            var score = Self.urgencyScore(percent: percent(for: mode), mode: mode)
            if let rl = rateLimits {
                let window = mode == .sevenDay ? RateLimitUsage.sevenDayWindow : RateLimitUsage.fiveHourWindow
                if mode == .fiveHour || mode == .sevenDay,
                   let ttl = rl.estimatedTimeToLimit(for: window) {
                    // Boost: <30min → +0.20, <2h → +0.10, <6h → +0.05
                    let boost: Double
                    switch ttl {
                    case ..<(30 * 60):    boost = 0.20
                    case ..<(2 * 3600):   boost = 0.10
                    case ..<(6 * 3600):   boost = 0.05
                    default:              boost = 0.0
                    }
                    score += boost
                }
            }
            return (mode, score)
        }
        let maxUrgency = scored.map(\.1).max() ?? 0
        // Among tied modes, prefer context > 5h > 7d (most actionable first)
        let tiePriority: [MetricMode] = [.contextHealth, .fiveHour, .sevenDay]
        return scored
            .filter { $0.1 == maxUrgency }
            .min { (tiePriority.firstIndex(of: $0.0) ?? .max) < (tiePriority.firstIndex(of: $1.0) ?? .max) }!
            .0
    }

    // MARK: - Urgency scoring

    /// Maps a raw percentage to a normalized 0.0–1.0 urgency score using mode-specific
    /// piecewise-linear interpolation. This ensures "first warning" aligns at 0.25 across
    /// all modes despite different threshold scales.
    static func urgencyScore(percent: Double, mode: MetricMode) -> Double {
        let anchors: [(Double, Double)]
        switch mode {
        case .fiveHour, .sevenDay:
            anchors = [(0, 0), (50, 0.25), (80, 0.50), (95, 0.75), (100, 1.0)]
        case .contextHealth:
            anchors = [(0, 0), (60, 0.25), (80, 0.50), (100, 1.0)]
        }
        return interpolate(percent, anchors: anchors)
    }

    /// Piecewise-linear interpolation. Values below first anchor clamp to 0, above last to 1.
    private static func interpolate(_ value: Double, anchors: [(Double, Double)]) -> Double {
        guard !anchors.isEmpty else { return 0 }
        if value <= anchors.first!.0 { return anchors.first!.1 }
        if value >= anchors.last!.0 { return anchors.last!.1 }
        for i in 0..<(anchors.count - 1) {
            let (x0, y0) = anchors[i]
            let (x1, y1) = anchors[i + 1]
            if value >= x0 && value <= x1 {
                let t = (value - x0) / (x1 - x0)
                return y0 + t * (y1 - y0)
            }
        }
        return anchors.last!.1
    }

    // Daily activity for chart
    let dailyActivity: [DailyActivity]

    // MARK: - Projections & trends

    /// Average messages per day over the last 7 days of activity.
    /// Pre-computed at construction to avoid per-render iteration.
    let dailyAverage: Int

    /// Trend direction comparing this week's average to last week's.
    /// Pre-computed at construction to avoid per-render iteration.
    let trendDirection: TrendDirection

    /// Busiest day of the week based on daily activity history.
    /// Pre-computed at construction to avoid iterating all dailyActivity on every view render.
    let busiestDayOfWeek: (name: String, averageCount: Int)?

    /// Compute daily average, trend direction, and busiest day in a single pass.
    static func computeActivityStats(_ dailyActivity: [DailyActivity])
        -> (average: Int, trend: TrendDirection, busiestDay: (name: String, averageCount: Int)?) {
        guard !dailyActivity.isEmpty else { return (0, .flat, nil) }

        let count = dailyActivity.count
        let calendar = Calendar.current

        // Accumulators for all three metrics
        var recentTotal = 0
        var thisWeekTotal = 0
        var lastWeekTotal = 0
        var weekdayTotals = [Int: Int]()
        var weekdayCounts = [Int: Int]()

        let recentStart = max(0, count - 7)
        let thisWeekStart = max(0, count - 7)
        let lastWeekStart = max(0, count - 14)
        let lastWeekEnd = max(0, count - 7)

        for (i, day) in dailyActivity.enumerated() {
            // Daily average (last 7)
            if i >= recentStart {
                recentTotal += day.messageCount
            }
            // Trend: this week vs last week (need >= 14 days)
            if count >= 14 {
                if i >= thisWeekStart {
                    thisWeekTotal += day.messageCount
                } else if i >= lastWeekStart && i < lastWeekEnd {
                    lastWeekTotal += day.messageCount
                }
            }
            // Busiest day
            if let date = day.parsedDate {
                let weekday = calendar.component(.weekday, from: date)
                weekdayTotals[weekday, default: 0] += day.messageCount
                weekdayCounts[weekday, default: 0] += 1
            }
        }

        // Average
        let recentCount = count - recentStart
        let average = recentCount > 0 ? recentTotal / recentCount : 0

        // Trend
        let trend: TrendDirection
        if count < 14 {
            trend = .flat
        } else {
            let thisWeekDays = count - thisWeekStart
            let lastWeekDays = lastWeekEnd - lastWeekStart
            let thisAvg = Double(thisWeekTotal) / Double(thisWeekDays)
            let lastAvg = Double(lastWeekTotal) / Double(max(lastWeekDays, 1))
            if lastAvg <= 0 {
                trend = thisAvg > 0 ? .up : .flat
            } else {
                let change = (thisAvg - lastAvg) / lastAvg
                if change > 0.10 { trend = .up }
                else if change < -0.10 { trend = .down }
                else { trend = .flat }
            }
        }

        // Busiest day
        let busiestDay: (name: String, averageCount: Int)?
        if let (weekday, total) = weekdayTotals.max(by: { a, b in
            let avgA = Double(a.value) / Double(weekdayCounts[a.key] ?? 1)
            let avgB = Double(b.value) / Double(weekdayCounts[b.key] ?? 1)
            return avgA < avgB
        }) {
            let avg = total / max(weekdayCounts[weekday] ?? 1, 1)
            let index = weekday - 1
            if avg > 0, index >= 0, index < weekdaySymbols.count {
                busiestDay = (weekdaySymbols[index], avg)
            } else {
                busiestDay = nil
            }
        } else {
            busiestDay = nil
        }

        return (average, trend, busiestDay)
    }

    // Hourly message distribution (hour "0"-"23" → count, all-time merged)
    let hourCounts: [String: Int]

    // Today's hourly breakdown (hour "0"-"23" → count, from JSONL only)
    let todayHourCounts: [String: Int]

    // Token health for the most recent session (last JSONL entry's session)
    let tokenHealth: TokenHealthStatus?

    // Top sessions sorted by highest context usage (up to 5, within last 24h)
    let topSessionHealths: [TokenHealthStatus]

}

struct ModelTokenSummary: Identifiable {
    let id: String // model ID
    let displayName: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int

    var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens
    }
}

