import Testing
import Foundation
@testable import AIBatteryCore

@Suite("ActivityChartData")
struct ActivityChartDataTests {

    // MARK: - Seven day data

    @Test func sevenDayData_returns7Days() {
        let data = ActivityChartData.sevenDayData(from: [:])
        #expect(data.count == 7)
    }

    @Test func sevenDayData_fillsGapsWithZero() {
        let now = Date()
        let todayKey = DateFormatters.dateKey.string(from: now)
        let tokens: [String: Int] = [todayKey: 5000]
        let data = ActivityChartData.sevenDayData(from: tokens, now: now)

        // Today should have 5000, all others should be 0
        let todayPoint = data.first(where: { $0.key == todayKey })
        #expect(todayPoint?.count == 5000)

        let zeroDays = data.filter { $0.key != todayKey }
        #expect(zeroDays.allSatisfy { $0.count == 0 })
    }

    @Test func sevenDayData_orderedChronologically() {
        let data = ActivityChartData.sevenDayData(from: [:])
        for i in 1..<data.count {
            #expect(data[i].date > data[i - 1].date)
        }
    }

    // MARK: - Five hour data

    @Test func fiveHourData_returns20Points() {
        let data = ActivityChartData.fiveHourData(from: [:])
        #expect(data.count == 20)
    }

    @Test func fiveHourData_looksUpCorrectBuckets() {
        let buckets: [Int: Int] = [0: 1000, 19: 5000]
        let data = ActivityChartData.fiveHourData(from: buckets)

        // Bucket 0 (oldest) should be the first point
        let firstPoint = data.first!
        #expect(firstPoint.id == 0)
        #expect(firstPoint.count == 1000)

        // Bucket 19 (most recent) should be the last point
        let lastPoint = data.last!
        #expect(lastPoint.id == 19)
        #expect(lastPoint.count == 5000)
    }

    @Test func fiveHourData_zeroForMissingBuckets() {
        let data = ActivityChartData.fiveHourData(from: [:])
        #expect(data.allSatisfy { $0.count == 0 })
    }

    // MARK: - Month token totals

    @Test func monthTokenTotals_aggregatesCorrectly() {
        let daily: [String: Int] = [
            "2026-03-01": 10000,
            "2026-03-15": 20000,
            "2026-02-10": 5000,
        ]
        let totals = ActivityChartData.monthTokenTotals(from: daily)
        #expect(totals["2026-03"] == 30000)
        #expect(totals["2026-02"] == 5000)
    }

    @Test func monthTokenTotals_emptyInput() {
        let totals = ActivityChartData.monthTokenTotals(from: [:])
        #expect(totals.isEmpty)
    }

    @Test func monthTokenTotals_skipsInvalidDates() {
        let daily: [String: Int] = [
            "not-a-date": 10000,
            "2026-01-05": 7000,
        ]
        let totals = ActivityChartData.monthTokenTotals(from: daily)
        #expect(totals.count == 1)
        #expect(totals["2026-01"] == 7000)
    }

    // MARK: - Monthly data

    @Test func monthlyData_returns12Months() {
        let data = ActivityChartData.monthlyData(from: [:])
        #expect(data.count == 12)
    }

    @Test func monthlyData_orderedChronologically() {
        let data = ActivityChartData.monthlyData(from: [:])
        for i in 1..<data.count {
            #expect(data[i].date > data[i - 1].date)
        }
    }

    @Test func monthlyData_projectsCurrentMonth() {
        let cal = Calendar.current
        // Fix to March 10, 2026 — so dayOfMonth=10, daysInMonth=31
        let fixedDate = cal.date(from: DateComponents(year: 2026, month: 3, day: 10))!
        let daily: [String: Int] = [
            "2026-03-01": 10000,
            "2026-03-05": 20000,
        ]
        let data = ActivityChartData.monthlyData(from: daily, now: fixedDate)
        let march = data.first(where: { $0.key == "2026-03" })!

        // Total is 30000, projected = 30000 * 31 / 10 = 93000
        #expect(march.count == 93000)
    }

    @Test func monthlyData_noProjectionFirstThreeDays() {
        let cal = Calendar.current
        let fixedDate = cal.date(from: DateComponents(year: 2026, month: 3, day: 2))!
        let daily: [String: Int] = [
            "2026-03-01": 10000,
        ]
        let data = ActivityChartData.monthlyData(from: daily, now: fixedDate)
        let march = data.first(where: { $0.key == "2026-03" })!

        // Day 2 < 4, so no projection — raw total
        #expect(march.count == 10000)
    }

    @Test func monthlyData_pastMonthsNotProjected() {
        let cal = Calendar.current
        let fixedDate = cal.date(from: DateComponents(year: 2026, month: 3, day: 15))!
        let daily: [String: Int] = [
            "2026-02-10": 50000,
        ]
        let data = ActivityChartData.monthlyData(from: daily, now: fixedDate)
        let feb = data.first(where: { $0.key == "2026-02" })!

        // Past month — no projection
        #expect(feb.count == 50000)
    }
}
