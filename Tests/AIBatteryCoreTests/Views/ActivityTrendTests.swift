import Testing
import Foundation
@testable import AIBatteryCore

@Suite("ActivityTrendComputation")
@MainActor
struct ActivityTrendTests {
    // MARK: - changeVsYesterday

    @Test func changeVsYesterday_positive() throws {
        let cal = Calendar.current
        let now = Date()
        let todayStr = DateFormatters.dateKey.string(from: now)
        let yesterdayStr = try DateFormatters.dateKey.string(from: #require(cal.date(byAdding: .day, value: -1, to: now)))
        let snapshot = makeSnapshot(dailyTokenTotals: [todayStr: 15_000, yesterdayStr: 10_000])
        let change = ActivityTrendComputation.changeVsYesterday(snapshot, cal: cal, now: now)
        #expect(change?.symbol == "↑")
        #expect(change?.label == "+50% vs yesterday")
    }

    @Test func changeVsYesterday_negative() throws {
        let cal = Calendar.current
        let now = Date()
        let todayStr = DateFormatters.dateKey.string(from: now)
        let yesterdayStr = try DateFormatters.dateKey.string(from: #require(cal.date(byAdding: .day, value: -1, to: now)))
        let snapshot = makeSnapshot(dailyTokenTotals: [todayStr: 5_000, yesterdayStr: 10_000])
        let change = ActivityTrendComputation.changeVsYesterday(snapshot, cal: cal, now: now)
        #expect(change?.symbol == "↓")
        #expect(change?.label == "-50% vs yesterday")
    }

    @Test func changeVsYesterday_same() throws {
        let cal = Calendar.current
        let now = Date()
        let todayStr = DateFormatters.dateKey.string(from: now)
        let yesterdayStr = try DateFormatters.dateKey.string(from: #require(cal.date(byAdding: .day, value: -1, to: now)))
        let snapshot = makeSnapshot(dailyTokenTotals: [todayStr: 10_000, yesterdayStr: 10_000])
        let change = ActivityTrendComputation.changeVsYesterday(snapshot, cal: cal, now: now)
        #expect(change?.symbol == "→")
    }

    @Test func changeVsYesterday_nilWhenNoYesterdayData() {
        let snapshot = makeSnapshot(dailyTokenTotals: [:])
        let change = ActivityTrendComputation.changeVsYesterday(snapshot)
        #expect(change == nil)
    }

    // MARK: - monthChangeInfo

    @Test func monthChange_positiveProjection() throws {
        let cal = Calendar.current
        // March 15, 2026 — dayOfMonth=15, daysInMonth=31
        let now = try #require(cal.date(from: DateComponents(year: 2_026, month: 3, day: 15)))
        // thisMonth=100, projected=100*31/15=206, lastMonth=100 → +106% → ↑
        let change = ActivityTrendComputation.monthChangeInfo(thisMonth: 100, lastMonth: 100, cal: cal, now: now)
        #expect(change?.symbol == "↑")
    }

    @Test func monthChange_nilWhenLastMonthZero() {
        let change = ActivityTrendComputation.monthChangeInfo(thisMonth: 50, lastMonth: 0)
        #expect(change == nil)
    }

    @Test func monthChange_nilWhenTooEarlyInMonth() throws {
        let cal = Calendar.current
        let now = try #require(cal.date(from: DateComponents(year: 2_026, month: 3, day: 2)))
        let change = ActivityTrendComputation.monthChangeInfo(thisMonth: 50, lastMonth: 100, cal: cal, now: now)
        #expect(change == nil) // dayOfMonth < 4
    }

    // MARK: - copyText

    @Test func copyText_includesAllParts() {
        let data = ActivityTrendData(
            change: ActivityChangeInfo(symbol: "↑", label: "+5 vs yesterday", color: .orange),
            stat: "15 msgs today",
            throttleCount: 2,
            peak: "Peak: 14:00",
            throttleDays: 1
        )
        let text = ActivityTrendComputation.copyText(data)
        #expect(text.contains("↑ +5 vs yesterday"))
        #expect(text.contains("15 msgs today"))
        #expect(text.contains("Throttled: 2×"))
        #expect(text.contains("Peak: 14:00"))
    }

    @Test func copyText_zeroThrottles() {
        let data = ActivityTrendData(
            change: nil,
            stat: nil,
            throttleCount: 0,
            peak: nil,
            throttleDays: 1
        )
        let text = ActivityTrendComputation.copyText(data)
        #expect(text == "Throttled: 0")
    }

    // MARK: - Helpers

    private func makeSnapshot(
        todayMessages: Int = 0,
        dailyActivity: [DailyActivity] = [],
        dailyTokenTotals: [String: Int] = [:]
    ) -> UsageSnapshot {
        let stats = UsageSnapshot.computeActivityStats(dailyActivity)
        return UsageSnapshot(
            lastUpdated: Date(),
            rateLimits: nil,
            rateLimitSource: nil,
            standardLimits: nil,
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
            modelTokens: [],
            projectTokens: [],
            totalTokens: 0,
            totalUsageTokens: 0,
            totalProjectTokens: 0,
            totalProjectUsageTokens: 0,
            totalProjectCost: 0,
            fiveHourTokens: 0,
            sevenDayTokens: 0,
            fiveHourTokenBuckets: [:],
            dailyTokenTotals: dailyTokenTotals,
            todayModelTokens: [],
            weekModelTokens: [],
            monthModelTokens: [],
            dailyActivity: dailyActivity,
            dailyAverage: stats.average,
            trendDirection: stats.trend,
            busiestDayOfWeek: stats.busiestDay,
            hourCounts: [:],
            todayHourCounts: [:],
            tokenHealth: nil,
            topSessionHealths: []
        )
    }
}
