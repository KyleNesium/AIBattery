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
    func percent(for mode: MetricMode) -> Double {
        switch mode {
        case .fiveHour: return rateLimits?.fiveHourPercent ?? 0
        case .sevenDay: return rateLimits?.sevenDayPercent ?? 0
        case .contextHealth: return tokenHealth?.usagePercentage ?? 0
        }
    }

    /// Auto mode: pick whichever metric has the highest percentage.
    var autoResolvedMode: MetricMode {
        let fiveHour = percent(for: .fiveHour)
        let sevenDay = percent(for: .sevenDay)
        let context = percent(for: .contextHealth)
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

    /// Compute daily average from activity data.
    static func computeDailyAverage(_ dailyActivity: [DailyActivity]) -> Int {
        let recent = dailyActivity.suffix(7)
        guard !recent.isEmpty else { return 0 }
        let total = recent.reduce(0) { $0 + $1.messageCount }
        return total / recent.count
    }

    /// Compute trend direction from activity data.
    static func computeTrendDirection(_ dailyActivity: [DailyActivity]) -> TrendDirection {
        let count = dailyActivity.count
        guard count >= 8 else { return .flat }

        let thisWeek = dailyActivity.suffix(7)
        let lastWeek = dailyActivity.dropLast(7).suffix(7)
        guard !lastWeek.isEmpty else { return .flat }

        let thisAvg = Double(thisWeek.reduce(0) { $0 + $1.messageCount }) / Double(thisWeek.count)
        let lastAvg = Double(lastWeek.reduce(0) { $0 + $1.messageCount }) / Double(lastWeek.count)

        guard lastAvg > 0 else { return thisAvg > 0 ? .up : .flat }
        let change = (thisAvg - lastAvg) / lastAvg
        if change > 0.10 { return .up }
        if change < -0.10 { return .down }
        return .flat
    }

    /// Compute the busiest day of the week from daily activity.
    static func computeBusiestDay(_ dailyActivity: [DailyActivity]) -> (name: String, averageCount: Int)? {
        let calendar = Calendar.current
        var totals = [Int: Int]()
        var counts = [Int: Int]()

        for day in dailyActivity {
            guard let date = day.parsedDate else { continue }
            let weekday = calendar.component(.weekday, from: date)
            totals[weekday, default: 0] += day.messageCount
            counts[weekday, default: 0] += 1
        }

        guard let (weekday, total) = totals.max(by: { a, b in
            let avgA = Double(a.value) / Double(counts[a.key] ?? 1)
            let avgB = Double(b.value) / Double(counts[b.key] ?? 1)
            return avgA < avgB
        }) else { return nil }

        let avg = total / max(counts[weekday] ?? 1, 1)
        guard avg > 0 else { return nil }

        let index = weekday - 1
        guard index >= 0, index < weekdaySymbols.count else { return nil }
        return (weekdaySymbols[index], avg)
    }

    // Hourly message distribution (hour "0"-"23" → count, from stats-cache)
    let hourCounts: [String: Int]

    // Token health for most recent session
    let tokenHealth: TokenHealthStatus?

    // Top sessions by most recent activity (up to 5, sorted newest first)
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

