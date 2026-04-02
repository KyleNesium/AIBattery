import Testing
import Foundation
@testable import AIBatteryCore

@Suite("ActivityTrendComputation")
@MainActor
struct ActivityTrendTests {

    // MARK: - changeVsYesterday

    @Test func changeVsYesterday_positive() {
        let cal = Calendar.current
        let now = Date()
        let yesterdayStr = DateFormatters.dateKey.string(from: cal.date(byAdding: .day, value: -1, to: now)!)
        let snapshot = makeSnapshot(todayMessages: 15, dailyActivity: [
            DailyActivity(date: yesterdayStr, messageCount: 10, sessionCount: 1, toolCallCount: 0)
        ])
        let change = ActivityTrendComputation.changeVsYesterday(snapshot, cal: cal, now: now)
        #expect(change?.symbol == "↑")
        #expect(change?.label == "+5 vs yesterday")
    }

    @Test func changeVsYesterday_negative() {
        let cal = Calendar.current
        let now = Date()
        let yesterdayStr = DateFormatters.dateKey.string(from: cal.date(byAdding: .day, value: -1, to: now)!)
        let snapshot = makeSnapshot(todayMessages: 5, dailyActivity: [
            DailyActivity(date: yesterdayStr, messageCount: 10, sessionCount: 1, toolCallCount: 0)
        ])
        let change = ActivityTrendComputation.changeVsYesterday(snapshot, cal: cal, now: now)
        #expect(change?.symbol == "↓")
        #expect(change?.label == "-5 vs yesterday")
    }

    @Test func changeVsYesterday_same() {
        let cal = Calendar.current
        let now = Date()
        let yesterdayStr = DateFormatters.dateKey.string(from: cal.date(byAdding: .day, value: -1, to: now)!)
        let snapshot = makeSnapshot(todayMessages: 10, dailyActivity: [
            DailyActivity(date: yesterdayStr, messageCount: 10, sessionCount: 1, toolCallCount: 0)
        ])
        let change = ActivityTrendComputation.changeVsYesterday(snapshot, cal: cal, now: now)
        #expect(change?.symbol == "→")
    }

    @Test func changeVsYesterday_nilWhenNoYesterdayData() {
        let snapshot = makeSnapshot(todayMessages: 10, dailyActivity: [])
        let change = ActivityTrendComputation.changeVsYesterday(snapshot)
        #expect(change == nil)
    }

    // MARK: - monthChangeInfo

    @Test func monthChange_positiveProjection() {
        let cal = Calendar.current
        // March 15, 2026 — dayOfMonth=15, daysInMonth=31
        let now = cal.date(from: DateComponents(year: 2026, month: 3, day: 15))!
        // thisMonth=100, projected=100*31/15=206, lastMonth=100 → +106% → ↑
        let change = ActivityTrendComputation.monthChangeInfo(thisMonth: 100, lastMonth: 100, cal: cal, now: now)
        #expect(change?.symbol == "↑")
    }

    @Test func monthChange_nilWhenLastMonthZero() {
        let change = ActivityTrendComputation.monthChangeInfo(thisMonth: 50, lastMonth: 0)
        #expect(change == nil)
    }

    @Test func monthChange_nilWhenTooEarlyInMonth() {
        let cal = Calendar.current
        let now = cal.date(from: DateComponents(year: 2026, month: 3, day: 2))!
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
        dailyActivity: [DailyActivity] = []
    ) -> UsageSnapshot {
        let stats = UsageSnapshot.computeActivityStats(dailyActivity)
        return UsageSnapshot(
            lastUpdated: Date(),
            rateLimits: nil,
            rateLimitSource: nil,
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
            totalProjectTokens: 0,
            totalProjectCost: 0,
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
