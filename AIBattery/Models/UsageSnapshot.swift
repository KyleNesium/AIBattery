import Foundation

struct UsageSnapshot {
    /// Reusable formatter for weekday symbol lookup — avoids allocating a new DateFormatter per call.
    private static let weekdayFormatter = DateFormatter()

    let lastUpdated: Date

    // Rate limit usage (from unified API response headers)
    let rateLimits: RateLimitUsage?

    // Account info
    let billingType: String?

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

    // Total tokens
    var totalTokens: Int {
        modelTokens.reduce(0) { $0 + $1.totalTokens }
    }

    /// The percentage for a given metric mode — shared by menu bar and popover.
    func percent(for mode: MetricMode) -> Double {
        switch mode {
        case .fiveHour: return rateLimits?.fiveHourPercent ?? 0
        case .sevenDay: return rateLimits?.sevenDayPercent ?? 0
        case .contextHealth: return tokenHealth?.usagePercentage ?? 0
        }
    }

    // Daily activity for chart
    let dailyActivity: [DailyActivity]

    // MARK: - Projections & trends

    /// Average messages per day over the last 7 days of activity.
    var dailyAverage: Int {
        let recent = dailyActivity.suffix(7)
        guard !recent.isEmpty else { return 0 }
        let total = recent.reduce(0) { $0 + $1.messageCount }
        return total / recent.count
    }

    /// Projected total messages for today based on hour-of-day progress.
    var projectedTodayTotal: Int {
        let hour = Calendar.current.component(.hour, from: Date())
        guard hour > 0, todayMessages > 0 else { return todayMessages }
        let fractionOfDay = Double(hour) / 24.0
        return Int(Double(todayMessages) / fractionOfDay)
    }

    /// Trend direction comparing this week's average to last week's.
    var trendDirection: TrendDirection {
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

    /// Busiest day of the week based on daily activity history.
    var busiestDayOfWeek: (name: String, averageCount: Int)? {
        let calendar = Calendar.current
        var totals = [Int: Int]()   // weekday → total messages
        var counts = [Int: Int]()   // weekday → number of occurrences

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

        let dayName = Self.weekdayFormatter.weekdaySymbols[weekday - 1]
        return (dayName, avg)
    }

    // Hourly message distribution (hour "0"-"23" → count, from stats-cache)
    let hourCounts: [String: Int]

    // Token health for most recent session
    let tokenHealth: TokenHealthStatus?

    // Top sessions by most recent activity (up to 5, sorted newest first)
    let topSessionHealths: [TokenHealthStatus]

    // Plan tier: billingType → stored preference → infer from rate limits
    var planTier: PlanTier? {
        if let tier = billingType.flatMap({ PlanTier.fromBillingType($0) }) {
            return tier
        }
        // Fall back to UserDefaults
        if let stored = UserDefaults.standard.string(forKey: UserDefaultsKeys.plan),
           let tier = PlanTier.fromBillingType(stored) {
            return tier
        }
        return nil
    }

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

    var shortLabel: String {
        switch self {
        case .fiveHour: return "5h"
        case .sevenDay: return "7d"
        case .contextHealth: return "Ctx"
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

/// Plan tier inferred from billing type string.
struct PlanTier {
    let name: String
    let price: String?

    static func fromBillingType(_ type: String) -> PlanTier? {
        switch type.lowercased() {
        case "pro": return PlanTier(name: "Pro", price: "$20/mo")
        case "max", "max_5x": return PlanTier(name: "Max", price: "$100/mo per seat")
        case "teams", "team": return PlanTier(name: "Teams", price: "$30/mo per seat")
        case "free": return PlanTier(name: "Free", price: nil)
        case "api_evaluation", "api": return PlanTier(name: "API", price: "Usage-based")
        case "": return nil
        default:
            // Unknown billing type — show capitalized name so new tiers aren't silently dropped
            let capitalized = type.prefix(1).uppercased() + type.dropFirst()
            return PlanTier(name: capitalized, price: nil)
        }
    }
}
