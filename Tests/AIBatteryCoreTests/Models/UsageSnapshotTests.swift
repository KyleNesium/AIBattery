import Foundation
import Testing
@testable import AIBatteryCore

@Suite("UsageSnapshot")
struct UsageSnapshotTests {

    private func makeSnapshot(
        modelTokens: [ModelTokenSummary] = [],
        rateLimits: RateLimitUsage? = nil,
        tokenHealth: TokenHealthStatus? = nil,
        todayMessages: Int = 0,
        dailyActivity: [DailyActivity] = []
    ) -> UsageSnapshot {
        UsageSnapshot(
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
            dailyAverage: UsageSnapshot.computeDailyAverage(dailyActivity),
            trendDirection: UsageSnapshot.computeTrendDirection(dailyActivity),
            busiestDayOfWeek: UsageSnapshot.computeBusiestDay(dailyActivity),
            hourCounts: [:],
            tokenHealth: tokenHealth,
            topSessionHealths: []
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
}
