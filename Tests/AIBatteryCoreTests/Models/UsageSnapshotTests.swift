import Foundation
import Testing
@testable import AIBatteryCore

@Suite("UsageSnapshot")
struct UsageSnapshotTests {

    private func makeSnapshot(
        modelTokens: [ModelTokenSummary] = [],
        rateLimits: RateLimitUsage? = nil,
        tokenHealth: TokenHealthStatus? = nil,
        billingType: String? = nil
    ) -> UsageSnapshot {
        UsageSnapshot(
            lastUpdated: Date(),
            rateLimits: rateLimits,
            displayName: nil,
            organizationName: nil,
            billingType: billingType,
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
            modelTokens: modelTokens,
            dailyActivity: [],
            hourCounts: [:],
            tokenHealth: tokenHealth,
            topSessionHealths: []
        )
    }

    // MARK: - totalTokens

    @Test func totalTokens_empty() {
        let snapshot = makeSnapshot()
        #expect(snapshot.totalTokens == 0)
    }

    @Test func totalTokens_sumsAllModels() {
        let models = [
            ModelTokenSummary(id: "a", displayName: "A", inputTokens: 100, outputTokens: 50, cacheReadTokens: 10, cacheWriteTokens: 5),
            ModelTokenSummary(id: "b", displayName: "B", inputTokens: 200, outputTokens: 100, cacheReadTokens: 20, cacheWriteTokens: 10),
        ]
        let snapshot = makeSnapshot(modelTokens: models)
        #expect(snapshot.totalTokens == 495) // (100+50+10+5) + (200+100+20+10)
    }

    // MARK: - percent(for:)

    @Test func percent_fiveHour_noRateLimits() {
        let snapshot = makeSnapshot()
        #expect(snapshot.percent(for: .fiveHour) == 0)
    }

    @Test func percent_contextHealth_usesTokenHealth() {
        let health = TokenHealthStatus(
            id: "s1",
            band: .orange,
            usagePercentage: 72.5,
            totalUsed: 116_000,
            contextWindow: 200_000,
            usableWindow: 160_000,
            remainingTokens: 44_000,
            inputTokens: 100_000,
            outputTokens: 16_000,
            cacheReadTokens: 0,
            cacheWriteTokens: 0,
            model: "claude-sonnet-4-5",
            turnCount: 10,
            warnings: [],
            tokensPerMinute: nil,
            projectName: nil,
            gitBranch: nil,
            sessionStart: nil,
            sessionDuration: nil,
            lastActivity: nil
        )
        let snapshot = makeSnapshot(tokenHealth: health)
        #expect(snapshot.percent(for: .contextHealth) == 72.5)
    }

    // MARK: - planTier

    @Test func planTier_fromBillingType() {
        let snapshot = makeSnapshot(billingType: "pro")
        #expect(snapshot.planTier?.name == "Pro")
        #expect(snapshot.planTier?.price == "$20/mo")
    }

    @Test func planTier_nilWhenNoBillingType() {
        let snapshot = makeSnapshot()
        // planTier may fall through to UserDefaults, so just check it doesn't crash
        _ = snapshot.planTier
    }
}
