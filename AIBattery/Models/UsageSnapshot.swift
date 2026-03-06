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
    static let nearExhaustionThreshold = 90.0

    /// Auto mode: three-tier priority — throttling > near-exhaustion > highest metric.
    /// Rate limit exhaustion is a harder constraint than context health (no tokens = no work),
    /// so it supersedes context health when approaching or hitting the cap.
    var autoResolvedMode: MetricMode {
        // Tier 1: Throttled — hard constraint, tokens are prerequisite for any work
        if let rl = rateLimits, rl.isThrottled {
            return rl.representativeClaim == RateLimitUsage.sevenDayWindow
                ? .sevenDay : .fiveHour
        }

        let fiveHour = percent(for: .fiveHour)
        let sevenDay = percent(for: .sevenDay)
        let context = percent(for: .contextHealth)

        // Tier 2: Near-exhaustion — approaching hard cap is more urgent than context
        let maxRate = max(fiveHour, sevenDay)
        if maxRate >= Self.nearExhaustionThreshold && maxRate > context {
            return sevenDay >= fiveHour ? .sevenDay : .fiveHour
        }

        // Tier 3: Normal — highest metric wins, context breaks ties
        if context >= fiveHour && context >= sevenDay { return .contextHealth }
        if sevenDay >= fiveHour { return .sevenDay }
        return .fiveHour
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

/// Which metric drives the menu bar icon percentage and color.
enum MetricMode: String, CaseIterable {
    case fiveHour = "5h"
    case sevenDay = "7d"
    case contextHealth = "context"

    var label: String {
        switch self {
        case .fiveHour: return "5-Hour"
        case .sevenDay: return "7-Day"
        case .contextHealth: return "Context"
        }
    }

}

/// Usage trend direction (this week vs last week).
enum TrendDirection {
    case up, down, flat

    var symbol: String {
        switch self {
        case .up: return "\u{2191}"    // ↑
        case .down: return "\u{2193}"  // ↓
        case .flat: return "\u{2192}"  // →
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .up: return "increasing"
        case .down: return "decreasing"
        case .flat: return "stable"
        }
    }
}

