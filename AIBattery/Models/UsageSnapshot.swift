import Foundation

struct UsageSnapshot {
    let lastUpdated: Date

    // Rate limit usage (from unified API response headers)
    let rateLimits: RateLimitUsage?

    // Account info
    let displayName: String?
    let organizationName: String?
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
