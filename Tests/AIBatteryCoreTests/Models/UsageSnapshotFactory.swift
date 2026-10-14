import Foundation
@testable import AIBatteryCore

/// A snapshot with everything zeroed except the handful of fields a test cares about.
/// `UsageSnapshot`'s initializer takes ~40 arguments; spelling it out per suite buried
/// the one line that mattered.
enum UsageSnapshotFactory {
    static func make(
        fiveHourTokens: Int = 0,
        sevenDayTokens: Int = 0,
        todayTokens: Int = 0,
        provider: AIProvider = .claude
    ) -> UsageSnapshot {
        let today: [ModelTokenSummary] = todayTokens == 0 ? [] : [
            ModelTokenSummary(
                id: provider == .codex ? "gpt-6-astra" : "claude-opus-5",
                displayName: "Test",
                inputTokens: todayTokens,
                outputTokens: 0,
                cacheReadTokens: 0,
                cacheWriteTokens: 0,
                estimatedCost: 0
            ),
        ]
        return UsageSnapshot(
            lastUpdated: Date(),
            rateLimits: nil,
            rateLimitSource: nil,
            standardLimits: nil,
            rateLimitsFresh: true,
            firstSessionDate: nil,
            totalSessions: 0,
            totalMessages: 0,
            longestSessionDuration: nil,
            longestSessionMessages: 0,
            peakHour: nil,
            peakHourCount: 0,
            todayMessages: 0,
            todaySessions: 0,
            todayToolCalls: 0,
            modelTokens: [],
            projectTokens: [],
            totalTokens: 0,
            totalUsageTokens: 0,
            totalProjectTokens: 0,
            totalProjectUsageTokens: 0,
            totalProjectCost: 0,
            fiveHourTokens: fiveHourTokens,
            sevenDayTokens: sevenDayTokens,
            fiveHourTokenBuckets: [:],
            dailyTokenTotals: [:],
            todayModelTokens: today,
            weekModelTokens: [],
            monthModelTokens: [],
            dailyActivity: [],
            dailyAverage: 0,
            trendDirection: .flat,
            busiestDayOfWeek: nil,
            hourCounts: [:],
            todayHourCounts: [:],
            tokenHealth: nil,
            topSessionHealths: [],
            provider: provider
        )
    }
}
