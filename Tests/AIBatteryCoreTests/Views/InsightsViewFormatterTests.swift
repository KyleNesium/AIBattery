import Testing
import Foundation
@testable import AIBatteryCore

@Suite("InsightsViewFormatter")
struct InsightsViewFormatterTests {
    // MARK: - CHART-02: formatHourLabelFull

    @Test func formatHourLabelFull_midnight_returns_00colon00() {
        #expect(InsightsView.formatHourLabelFull(0) == "00:00")
    }

    @Test func formatHourLabelFull_6am_returns_06colon00() {
        #expect(InsightsView.formatHourLabelFull(6) == "06:00")
    }

    @Test func formatHourLabelFull_noon_returns_12colon00() {
        #expect(InsightsView.formatHourLabelFull(12) == "12:00")
    }

    @Test func formatHourLabelFull_6pm_returns_18colon00() {
        #expect(InsightsView.formatHourLabelFull(18) == "18:00")
    }

    @Test func formatHourLabelFull_11pm_returns_23colon00() {
        #expect(InsightsView.formatHourLabelFull(23) == "23:00")
    }

    // MARK: - CHART-01: quarterlyLabelDates

    // Helper: build a 12-month Date array ending at the given year/month
    private func make12MonthDates(endingYear: Int, endingMonth: Int) -> [Date] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var components = DateComponents()
        components.day = 1
        components.hour = 0
        components.minute = 0
        components.second = 0
        var dates: [Date] = []
        for offset in stride(from: -11, through: 0, by: 1) {
            var m = endingMonth + offset
            var y = endingYear
            while m <= 0 {
                m += 12; y -= 1
            }
            while m > 12 {
                m -= 12; y += 1
            }
            components.year = y
            components.month = m
            dates.append(cal.date(from: components)!)
        }
        return dates
    }

    // March 2026: window is Apr 2025 – Mar 2026
    // Quarterly in window: Apr(4), Jul(7), Oct(10), Jan(1) → 4 quarterly
    // Current = Mar(3), not quarterly → 5 labels total
    @Test func quarterlyLabelDates_march2026_returns5Labels() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try #require(TimeZone(identifier: "UTC"))
        let comps = DateComponents(year: 2_026, month: 3, day: 15)
        let march2026 = try #require(cal.date(from: comps))
        let dates = make12MonthDates(endingYear: 2_026, endingMonth: 3)
        let labels = InsightsView.quarterlyLabelDates(from: dates, now: march2026)
        #expect(labels.count == 5)
    }

    // April 2026: window is May 2025 – Apr 2026
    // Quarterly in window: Jul(7), Oct(10), Jan(1), Apr(4) → 4 quarterly
    // Current = Apr(4), IS quarterly → 4 labels total (no duplicate)
    @Test func quarterlyLabelDates_april2026_returns4Labels() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try #require(TimeZone(identifier: "UTC"))
        let comps = DateComponents(year: 2_026, month: 4, day: 15)
        let april2026 = try #require(cal.date(from: comps))
        let dates = make12MonthDates(endingYear: 2_026, endingMonth: 4)
        let labels = InsightsView.quarterlyLabelDates(from: dates, now: april2026)
        #expect(labels.count == 4)
    }

    // Current month must always appear in the label set
    @Test func quarterlyLabelDates_currentMonthAlwaysIncluded() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try #require(TimeZone(identifier: "UTC"))
        let comps = DateComponents(year: 2_026, month: 3, day: 15)
        let march2026 = try #require(cal.date(from: comps))
        let dates = make12MonthDates(endingYear: 2_026, endingMonth: 3)
        let labels = InsightsView.quarterlyLabelDates(from: dates, now: march2026)
        // The last date in the array is the current month (Mar 2026)
        let currentMonthDate = try #require(dates.last)
        #expect(labels.contains(currentMonthDate))
    }
}
