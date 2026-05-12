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
        let tokens: [String: Int] = [todayKey: 5_000]
        let data = ActivityChartData.sevenDayData(from: tokens, now: now)

        // Today should have 5000, all others should be 0
        let todayPoint = data.first(where: { $0.key == todayKey })
        #expect(todayPoint?.count == 5_000)

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

    @Test func fiveHourData_looksUpCorrectBuckets() throws {
        let buckets: [Int: Int] = [0: 1_000, 19: 5_000]
        let data = ActivityChartData.fiveHourData(from: buckets)

        // Bucket 0 (oldest) should be the first point
        let firstPoint = try #require(data.first)
        #expect(firstPoint.id == 0)
        #expect(firstPoint.count == 1_000)

        // Bucket 19 (most recent) should be the last point
        let lastPoint = try #require(data.last)
        #expect(lastPoint.id == 19)
        #expect(lastPoint.count == 5_000)
    }

    @Test func fiveHourData_zeroForMissingBuckets() {
        let data = ActivityChartData.fiveHourData(from: [:])
        #expect(data.allSatisfy { $0.count == 0 })
    }

    // MARK: - Month token totals

    @Test func monthTokenTotals_aggregatesCorrectly() {
        let daily: [String: Int] = [
            "2026-03-01": 10_000,
            "2026-03-15": 20_000,
            "2026-02-10": 5_000,
        ]
        let totals = ActivityChartData.monthTokenTotals(from: daily)
        #expect(totals["2026-03"] == 30_000)
        #expect(totals["2026-02"] == 5_000)
    }

    @Test func monthTokenTotals_emptyInput() {
        let totals = ActivityChartData.monthTokenTotals(from: [:])
        #expect(totals.isEmpty)
    }

    @Test func monthTokenTotals_skipsInvalidDates() {
        let daily: [String: Int] = [
            "not-a-date": 10_000,
            "2026-01-05": 7_000,
        ]
        let totals = ActivityChartData.monthTokenTotals(from: daily)
        #expect(totals.count == 1)
        #expect(totals["2026-01"] == 7_000)
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

    @Test func monthlyData_projectsCurrentMonth() throws {
        let cal = Calendar.current
        // Fix to March 10, 2026 — so dayOfMonth=10, daysInMonth=31
        let fixedDate = try #require(cal.date(from: DateComponents(year: 2_026, month: 3, day: 10)))
        // monthlyData expects pre-aggregated month keys (from monthTokenTotals)
        let monthTotals: [String: Int] = [
            "2026-03": 30_000,
        ]
        let data = ActivityChartData.monthlyData(from: monthTotals, now: fixedDate)
        let march = try #require(data.first(where: { $0.key == "2026-03" }))

        // Total is 30000, projected = 30000 * 31 / 10 = 93000
        #expect(march.count == 93_000)
    }

    @Test func monthlyData_noProjectionFirstThreeDays() throws {
        let cal = Calendar.current
        let fixedDate = try #require(cal.date(from: DateComponents(year: 2_026, month: 3, day: 2)))
        let monthTotals: [String: Int] = [
            "2026-03": 10_000,
        ]
        let data = ActivityChartData.monthlyData(from: monthTotals, now: fixedDate)
        let march = try #require(data.first(where: { $0.key == "2026-03" }))

        // Day 2 < 4, so no projection — raw total
        #expect(march.count == 10_000)
    }

    @Test func monthlyData_pastMonthsNotProjected() throws {
        let cal = Calendar.current
        let fixedDate = try #require(cal.date(from: DateComponents(year: 2_026, month: 3, day: 15)))
        let monthTotals: [String: Int] = [
            "2026-02": 50_000,
        ]
        let data = ActivityChartData.monthlyData(from: monthTotals, now: fixedDate)
        let feb = try #require(data.first(where: { $0.key == "2026-02" }))

        // Past month — no projection
        #expect(feb.count == 50_000)
    }
}
