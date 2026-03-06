import Foundation
import Testing
@testable import AIBatteryCore

@Suite("UsageSnapshot")
struct UsageSnapshotTests {

    private func makeSnapshot(
        modelTokens: [ModelTokenSummary] = [],
        rateLimits: RateLimitUsage? = nil,
        tokenHealth: TokenHealthStatus? = nil,
        topSessionHealths: [TokenHealthStatus] = [],
        todayMessages: Int = 0,
        dailyActivity: [DailyActivity] = []
    ) -> UsageSnapshot {
        let activityStats = UsageSnapshot.computeActivityStats(dailyActivity)
        return UsageSnapshot(
            lastUpdated: Date(),
            rateLimits: rateLimits,
            firstSessionDate: nil,
            totalSessions: 0,
            totalMessages: 0,
            longestSessionDuration: nil,
            longestSessionMessages: 0,
            peakHour: nil,
            peakHourCount: 0,
            todayMessages: todayMessages,
            todaySessions: 0,
            todayToolCalls: 0,
            modelTokens: modelTokens,
            totalTokens: modelTokens.reduce(0) { $0 + $1.totalTokens },
            dailyActivity: dailyActivity,
            dailyAverage: activityStats.average,
            trendDirection: activityStats.trend,
            busiestDayOfWeek: activityStats.busiestDay,
            hourCounts: [:],
            todayHourCounts: [:],
            tokenHealth: tokenHealth,
            topSessionHealths: topSessionHealths
        )
    }

    private func makeHealth(id: String, usagePercentage: Double, band: HealthBand = .green) -> TokenHealthStatus {
        TokenHealthStatus(
            id: id, band: band, usagePercentage: usagePercentage,
            totalUsed: 0, contextWindow: 200_000, usableWindow: 160_000, remainingTokens: 0,
            inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0,
            model: "claude-sonnet-4-5", turnCount: 1, warnings: [],
            tokensPerMinute: nil, projectName: nil, gitBranch: nil,
            sessionStart: nil, sessionDuration: nil, lastActivity: nil
        )
    }

    private func makeDailyActivity(daysBack: Int, messages: [Int]) -> [DailyActivity] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return messages.enumerated().map { index, count in
            let date = Calendar.current.date(byAdding: .day, value: -(daysBack - 1 - index), to: Date())!
            return DailyActivity(date: formatter.string(from: date), messageCount: count, sessionCount: 1, toolCallCount: 0)
        }
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

    // MARK: - percent(for:) — rate limits

    @Test func percent_fiveHour_withRateLimits() {
        let limits = RateLimitUsage(
            representativeClaim: "five_hour",
            fiveHourUtilization: 0.42,
            fiveHourReset: nil,
            fiveHourStatus: "allowed",
            sevenDayUtilization: 0.05,
            sevenDayReset: nil,
            sevenDayStatus: "allowed",
            overallStatus: "allowed"
        )
        let snapshot = makeSnapshot(rateLimits: limits)
        #expect(snapshot.percent(for: .fiveHour) == 42.0)
    }

    @Test func percent_sevenDay_withRateLimits() {
        let limits = RateLimitUsage(
            representativeClaim: "seven_day",
            fiveHourUtilization: 0.10,
            fiveHourReset: nil,
            fiveHourStatus: "allowed",
            sevenDayUtilization: 0.88,
            sevenDayReset: nil,
            sevenDayStatus: "allowed",
            overallStatus: "allowed"
        )
        let snapshot = makeSnapshot(rateLimits: limits)
        #expect(snapshot.percent(for: .sevenDay) == 88.0)
    }

    @Test func percent_contextHealth_nilHealth() {
        let snapshot = makeSnapshot()
        #expect(snapshot.percent(for: .contextHealth) == 0)
    }

    @Test func percent_contextHealth_prefersHighestTopSession() {
        let current = makeHealth(id: "current", usagePercentage: 15.0)
        let highSession = makeHealth(id: "old", usagePercentage: 80.0, band: .red)
        let snapshot = makeSnapshot(
            tokenHealth: current,
            topSessionHealths: [highSession, current]
        )
        // Should use the highest from topSessionHealths (80%), not tokenHealth (15%)
        #expect(snapshot.percent(for: .contextHealth) == 80.0)
    }

    @Test func percent_contextHealth_fallsBackToTokenHealth() {
        let current = makeHealth(id: "current", usagePercentage: 45.0)
        // topSessionHealths empty, should fall back to tokenHealth
        let snapshot = makeSnapshot(tokenHealth: current, topSessionHealths: [])
        #expect(snapshot.percent(for: .contextHealth) == 45.0)
    }

    @Test func autoResolvedMode_picksContextHealthWhenHighest() {
        let limits = RateLimitUsage(
            representativeClaim: "five_hour",
            fiveHourUtilization: 0.20,
            fiveHourReset: nil,
            fiveHourStatus: "allowed",
            sevenDayUtilization: 0.30,
            sevenDayReset: nil,
            sevenDayStatus: "allowed",
            overallStatus: "allowed"
        )
        let highSession = makeHealth(id: "s1", usagePercentage: 75.0, band: .orange)
        let snapshot = makeSnapshot(
            rateLimits: limits,
            topSessionHealths: [highSession]
        )
        #expect(snapshot.autoResolvedMode == .contextHealth)
        #expect(snapshot.percent(for: .contextHealth) == 75.0)
    }

    @Test func autoResolvedMode_picksRateLimitOverLowContextHealth() {
        let limits = RateLimitUsage(
            representativeClaim: "five_hour",
            fiveHourUtilization: 0.60,
            fiveHourReset: nil,
            fiveHourStatus: "allowed",
            sevenDayUtilization: 0.10,
            sevenDayReset: nil,
            sevenDayStatus: "allowed",
            overallStatus: "allowed"
        )
        let lowSession = makeHealth(id: "s1", usagePercentage: 10.0)
        let snapshot = makeSnapshot(
            rateLimits: limits,
            topSessionHealths: [lowSession]
        )
        #expect(snapshot.autoResolvedMode == .fiveHour)
    }

    // MARK: - autoResolvedMode priority tiers

    @Test func autoResolvedMode_throttled_alwaysShowsRateLimit() {
        let limits = RateLimitUsage(
            representativeClaim: "five_hour",
            fiveHourUtilization: 1.0,
            fiveHourReset: Date().addingTimeInterval(300),
            fiveHourStatus: "throttled",
            sevenDayUtilization: 0.30,
            sevenDayReset: nil,
            sevenDayStatus: "allowed",
            overallStatus: "throttled"
        )
        let session = makeHealth(id: "s1", usagePercentage: 50.0)
        let snapshot = makeSnapshot(rateLimits: limits, topSessionHealths: [session])
        #expect(snapshot.autoResolvedMode == .fiveHour)
    }

    @Test func autoResolvedMode_throttled_7day_showsSevenDay() {
        let limits = RateLimitUsage(
            representativeClaim: "seven_day",
            fiveHourUtilization: 0.50,
            fiveHourReset: nil,
            fiveHourStatus: "allowed",
            sevenDayUtilization: 1.0,
            sevenDayReset: Date().addingTimeInterval(3600),
            sevenDayStatus: "throttled",
            overallStatus: "throttled"
        )
        let session = makeHealth(id: "s1", usagePercentage: 80.0, band: .red)
        let snapshot = makeSnapshot(rateLimits: limits, topSessionHealths: [session])
        #expect(snapshot.autoResolvedMode == .sevenDay)
    }

    @Test func autoResolvedMode_nearExhaustion_prioritizesRateLimit() {
        let limits = RateLimitUsage(
            representativeClaim: "five_hour",
            fiveHourUtilization: 0.92,
            fiveHourReset: nil,
            fiveHourStatus: "allowed",
            sevenDayUtilization: 0.10,
            sevenDayReset: nil,
            sevenDayStatus: "allowed",
            overallStatus: "allowed"
        )
        let session = makeHealth(id: "s1", usagePercentage: 70.0, band: .orange)
        let snapshot = makeSnapshot(rateLimits: limits, topSessionHealths: [session])
        #expect(snapshot.autoResolvedMode == .fiveHour)
    }

    @Test func autoResolvedMode_nearExhaustion_contextStillWinsIfHigher() {
        let limits = RateLimitUsage(
            representativeClaim: "five_hour",
            fiveHourUtilization: 0.92,
            fiveHourReset: nil,
            fiveHourStatus: "allowed",
            sevenDayUtilization: 0.10,
            sevenDayReset: nil,
            sevenDayStatus: "allowed",
            overallStatus: "allowed"
        )
        let session = makeHealth(id: "s1", usagePercentage: 95.0, band: .red)
        let snapshot = makeSnapshot(rateLimits: limits, topSessionHealths: [session])
        #expect(snapshot.autoResolvedMode == .contextHealth)
    }

    @Test func autoResolvedMode_throttled_overridesEvenFullContext() {
        let limits = RateLimitUsage(
            representativeClaim: "five_hour",
            fiveHourUtilization: 1.0,
            fiveHourReset: Date().addingTimeInterval(300),
            fiveHourStatus: "throttled",
            sevenDayUtilization: 0.30,
            sevenDayReset: nil,
            sevenDayStatus: "allowed",
            overallStatus: "throttled"
        )
        let session = makeHealth(id: "s1", usagePercentage: 100.0, band: .red)
        let snapshot = makeSnapshot(rateLimits: limits, topSessionHealths: [session])
        #expect(snapshot.autoResolvedMode == .fiveHour)
    }

    @Test func autoResolvedMode_nearExhaustion_bothWindowsHigh_picksHigher() {
        let limits = RateLimitUsage(
            representativeClaim: "five_hour",
            fiveHourUtilization: 0.92,
            fiveHourReset: nil,
            fiveHourStatus: "allowed",
            sevenDayUtilization: 0.95,
            sevenDayReset: nil,
            sevenDayStatus: "allowed",
            overallStatus: "allowed"
        )
        let session = makeHealth(id: "s1", usagePercentage: 70.0, band: .orange)
        let snapshot = makeSnapshot(rateLimits: limits, topSessionHealths: [session])
        // 7d (95%) > 5h (92%), both above threshold, both above context (70%)
        #expect(snapshot.autoResolvedMode == .sevenDay)
    }

    @Test func autoResolvedMode_belowThreshold_normalBehavior() {
        let limits = RateLimitUsage(
            representativeClaim: "five_hour",
            fiveHourUtilization: 0.85,
            fiveHourReset: nil,
            fiveHourStatus: "allowed",
            sevenDayUtilization: 0.10,
            sevenDayReset: nil,
            sevenDayStatus: "allowed",
            overallStatus: "allowed"
        )
        let session = makeHealth(id: "s1", usagePercentage: 88.0, band: .red)
        let snapshot = makeSnapshot(rateLimits: limits, topSessionHealths: [session])
        #expect(snapshot.autoResolvedMode == .contextHealth)
    }

    // MARK: - dailyAverage

    @Test func dailyAverage_emptyActivity() {
        let snapshot = makeSnapshot()
        #expect(snapshot.dailyAverage == 0)
    }

    @Test func dailyAverage_sevenDays() {
        let activity = makeDailyActivity(daysBack: 7, messages: [10, 20, 30, 40, 50, 60, 70])
        let snapshot = makeSnapshot(dailyActivity: activity)
        #expect(snapshot.dailyAverage == 40) // 280 / 7
    }

    @Test func dailyAverage_moreThanSevenDays_usesLastSeven() {
        let activity = makeDailyActivity(daysBack: 10, messages: [100, 100, 100, 10, 20, 30, 40, 50, 60, 70])
        let snapshot = makeSnapshot(dailyActivity: activity)
        #expect(snapshot.dailyAverage == 40) // last 7: 10+20+30+40+50+60+70 = 280 / 7
    }

    // MARK: - trendDirection

    @Test func trendDirection_insufficientData() {
        let activity = makeDailyActivity(daysBack: 5, messages: [10, 20, 30, 40, 50])
        let snapshot = makeSnapshot(dailyActivity: activity)
        #expect(snapshot.trendDirection == .flat)
    }

    @Test func trendDirection_13days_insufficientForSymmetricComparison() {
        // 13 days is not enough for a full 7-vs-7 comparison
        let activity = makeDailyActivity(daysBack: 13, messages: [
            10, 10, 10, 10, 10, 10,  // 6 days of "last week"
            50, 50, 50, 50, 50, 50, 50,  // 7 days of "this week"
        ])
        let snapshot = makeSnapshot(dailyActivity: activity)
        #expect(snapshot.trendDirection == .flat)
    }

    @Test func trendDirection_upWhenThisWeekHigher() {
        // Last week: 10/day avg, This week: 50/day avg → clearly up
        let activity = makeDailyActivity(daysBack: 14, messages: [
            10, 10, 10, 10, 10, 10, 10,  // last week
            50, 50, 50, 50, 50, 50, 50,  // this week
        ])
        let snapshot = makeSnapshot(dailyActivity: activity)
        #expect(snapshot.trendDirection == .up)
    }

    @Test func trendDirection_downWhenThisWeekLower() {
        let activity = makeDailyActivity(daysBack: 14, messages: [
            50, 50, 50, 50, 50, 50, 50,  // last week
            10, 10, 10, 10, 10, 10, 10,  // this week
        ])
        let snapshot = makeSnapshot(dailyActivity: activity)
        #expect(snapshot.trendDirection == .down)
    }

    @Test func trendDirection_flatWhenSimilar() {
        let activity = makeDailyActivity(daysBack: 14, messages: [
            50, 50, 50, 50, 50, 50, 50,
            50, 50, 50, 50, 50, 50, 50,
        ])
        let snapshot = makeSnapshot(dailyActivity: activity)
        #expect(snapshot.trendDirection == .flat)
    }

    // MARK: - busiestDayOfWeek

    @Test func busiestDayOfWeek_emptyActivity() {
        let snapshot = makeSnapshot()
        #expect(snapshot.busiestDayOfWeek == nil)
    }

    @Test func busiestDayOfWeek_returnsDay() {
        let activity = makeDailyActivity(daysBack: 7, messages: [10, 10, 10, 100, 10, 10, 10])
        let snapshot = makeSnapshot(dailyActivity: activity)
        let busiest = snapshot.busiestDayOfWeek
        #expect(busiest != nil)
        #expect(busiest!.averageCount > 0)
    }

    // MARK: - TrendDirection symbols

    @Test func trendDirection_symbols() {
        #expect(!TrendDirection.up.symbol.isEmpty)
        #expect(!TrendDirection.down.symbol.isEmpty)
        #expect(!TrendDirection.flat.symbol.isEmpty)
        #expect(TrendDirection.up.symbol != TrendDirection.down.symbol)
    }

    // MARK: - computeActivityStats (single-pass)

    @Test func activityStats_emptyActivity() {
        let stats = UsageSnapshot.computeActivityStats([])
        #expect(stats.average == 0)
        #expect(stats.trend == .flat)
        #expect(stats.busiestDay == nil)
    }

    @Test func activityStats_singleWeek() {
        let activity = makeDailyActivity(daysBack: 7, messages: [10, 20, 30, 40, 50, 60, 70])
        let stats = UsageSnapshot.computeActivityStats(activity)
        #expect(stats.average == 40) // 280 / 7
        #expect(stats.trend == .flat) // < 14 days
        #expect(stats.busiestDay != nil)
        #expect(stats.busiestDay!.averageCount > 0)
    }

    @Test func activityStats_multiWeek_trendUp() {
        let activity = makeDailyActivity(daysBack: 14, messages: [
            10, 10, 10, 10, 10, 10, 10,  // last week
            50, 50, 50, 50, 50, 50, 50,  // this week
        ])
        let stats = UsageSnapshot.computeActivityStats(activity)
        #expect(stats.average == 50) // last 7: all 50
        #expect(stats.trend == .up)
        #expect(stats.busiestDay != nil)
    }

    @Test func activityStats_multiWeek_trendDown() {
        let activity = makeDailyActivity(daysBack: 14, messages: [
            50, 50, 50, 50, 50, 50, 50,
            10, 10, 10, 10, 10, 10, 10,
        ])
        let stats = UsageSnapshot.computeActivityStats(activity)
        #expect(stats.average == 10)
        #expect(stats.trend == .down)
    }

    @Test func activityStats_matchesSnapshotProperties() {
        // Verify computeActivityStats produces same results as snapshot pre-computation.
        // Use asymmetric counts so one weekday is clearly the busiest (avoids tie-breaking nondeterminism).
        let activity = makeDailyActivity(daysBack: 14, messages: [
            10, 10, 10, 10, 10, 10, 10,
            50, 50, 50, 50, 50, 50, 99,
        ])
        let snapshot = makeSnapshot(dailyActivity: activity)
        let stats = UsageSnapshot.computeActivityStats(activity)
        #expect(snapshot.dailyAverage == stats.average)
        #expect(snapshot.trendDirection == stats.trend)
        // Busiest day name should match (both non-nil)
        #expect(snapshot.busiestDayOfWeek?.name == stats.busiestDay?.name)
        #expect(snapshot.busiestDayOfWeek?.averageCount == stats.busiestDay?.averageCount)
    }
}
