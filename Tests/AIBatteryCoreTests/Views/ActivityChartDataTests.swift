import Testing
import Foundation
@testable import AIBatteryCore

@Suite("ActivityChartData")
struct ActivityChartDataTests {

    // MARK: - Daily data

    @Test func dailyData_returns7Days() {
        let data = ActivityChartData.dailyData(from: [])
        #expect(data.count == 7)
    }

    @Test func dailyData_fillsGapsWithZero() {
        let now = Date()
        let todayKey = DateFormatters.dateKey.string(from: now)
        let activity = [DailyActivity(date: todayKey, messageCount: 5, sessionCount: 1, toolCallCount: 0)]
        let data = ActivityChartData.dailyData(from: activity, now: now)

        // Today should have 5, all others should be 0
        let todayPoint = data.first(where: { $0.key == todayKey })
        #expect(todayPoint?.count == 5)

        let zeroDays = data.filter { $0.key != todayKey }
        #expect(zeroDays.allSatisfy { $0.count == 0 })
    }

    @Test func dailyData_orderedChronologically() {
        let data = ActivityChartData.dailyData(from: [])
        for i in 1..<data.count {
            #expect(data[i].date > data[i - 1].date)
        }
    }

    // MARK: - Hourly data

    @Test func hourlyData_returns24Points() {
        let data = ActivityChartData.hourlyData(from: [:])
        #expect(data.count == 24)
    }

    @Test func hourlyData_looksUpCorrectHours() {
        let cal = Calendar.current
        // Fix to a known hour for deterministic testing
        let fixedDate = cal.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 14))!
        let counts: [String: Int] = ["14": 10, "3": 5]
        let data = ActivityChartData.hourlyData(from: counts, now: fixedDate)

        // Hour 14 (current) should be the last point
        let lastPoint = data.last!
        #expect(lastPoint.hour == 14)
        #expect(lastPoint.count == 10)

        // Hour 3 should also appear
        let hour3 = data.first(where: { $0.hour == 3 })
        #expect(hour3?.count == 5)
    }

    @Test func hourlyData_coversFullDay() {
        let cal = Calendar.current
        let fixedDate = cal.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 2))!
        let data = ActivityChartData.hourlyData(from: [:], now: fixedDate)

        // 24-hour window: should contain hours from 3 (yesterday) through 2 (today)
        let hours = data.map(\.hour)
        #expect(hours.first == 3) // 2 - 23 + 24 = 3
        #expect(hours.last == 2)
        // All 24 hours should be represented
        #expect(Set(hours).count == 24)
    }

    // MARK: - Month totals

    @Test func monthTotals_aggregatesCorrectly() {
        let activity = [
            DailyActivity(date: "2026-03-01", messageCount: 10, sessionCount: 1, toolCallCount: 0),
            DailyActivity(date: "2026-03-15", messageCount: 20, sessionCount: 2, toolCallCount: 0),
            DailyActivity(date: "2026-02-10", messageCount: 5, sessionCount: 1, toolCallCount: 0),
        ]
        let totals = ActivityChartData.monthTotals(from: activity)
        #expect(totals["2026-03"] == 30)
        #expect(totals["2026-02"] == 5)
    }

    @Test func monthTotals_emptyActivity() {
        let totals = ActivityChartData.monthTotals(from: [])
        #expect(totals.isEmpty)
    }

    @Test func monthTotals_skipsInvalidDates() {
        let activity = [
            DailyActivity(date: "not-a-date", messageCount: 10, sessionCount: 1, toolCallCount: 0),
            DailyActivity(date: "2026-01-05", messageCount: 7, sessionCount: 1, toolCallCount: 0),
        ]
        let totals = ActivityChartData.monthTotals(from: activity)
        #expect(totals.count == 1)
        #expect(totals["2026-01"] == 7)
    }

    // MARK: - Monthly data

    @Test func monthlyData_returns12Months() {
        let data = ActivityChartData.monthlyData(from: [])
        #expect(data.count == 12)
    }

    @Test func monthlyData_orderedChronologically() {
        let data = ActivityChartData.monthlyData(from: [])
        for i in 1..<data.count {
            #expect(data[i].date > data[i - 1].date)
        }
    }

    @Test func monthlyData_projectsCurrentMonth() {
        let cal = Calendar.current
        // Fix to March 10, 2026 — so dayOfMonth=10, daysInMonth=31
        let fixedDate = cal.date(from: DateComponents(year: 2026, month: 3, day: 10))!
        let activity = [
            DailyActivity(date: "2026-03-01", messageCount: 10, sessionCount: 1, toolCallCount: 0),
            DailyActivity(date: "2026-03-05", messageCount: 20, sessionCount: 2, toolCallCount: 0),
        ]
        let data = ActivityChartData.monthlyData(from: activity, now: fixedDate)
        let march = data.first(where: { $0.key == "2026-03" })!

        // Total is 30, projected = 30 * 31 / 10 = 93
        #expect(march.count == 93)
    }

    @Test func monthlyData_noProjectionFirstThreeDays() {
        let cal = Calendar.current
        let fixedDate = cal.date(from: DateComponents(year: 2026, month: 3, day: 2))!
        let activity = [
            DailyActivity(date: "2026-03-01", messageCount: 10, sessionCount: 1, toolCallCount: 0),
        ]
        let data = ActivityChartData.monthlyData(from: activity, now: fixedDate)
        let march = data.first(where: { $0.key == "2026-03" })!

        // Day 2 < 4, so no projection — raw total
        #expect(march.count == 10)
    }

    @Test func monthlyData_pastMonthsNotProjected() {
        let cal = Calendar.current
        let fixedDate = cal.date(from: DateComponents(year: 2026, month: 3, day: 15))!
        let activity = [
            DailyActivity(date: "2026-02-10", messageCount: 50, sessionCount: 5, toolCallCount: 0),
        ]
        let data = ActivityChartData.monthlyData(from: activity, now: fixedDate)
        let feb = data.first(where: { $0.key == "2026-02" })!

        // Past month — no projection
        #expect(feb.count == 50)
    }
}
