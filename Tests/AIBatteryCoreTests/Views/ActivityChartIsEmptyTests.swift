import Testing
import Foundation
@testable import AIBatteryCore

@Suite("ActivityChartIsEmpty")
struct ActivityChartIsEmptyTests {

    private var todayKey: String {
        DateFormatters.dateKey.string(from: Date())
    }
    private var yesterdayKey: String {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        return DateFormatters.dateKey.string(from: yesterday)
    }

    // DATA-01: empty hourCounts + today has daily activity → loading, not empty
    @Test func isHourlyEmpty_emptyHourCounts_withTodayActivity_returnsFalse() {
        let activity = [DailyActivity(date: todayKey, messageCount: 5, sessionCount: 1, toolCallCount: 0)]
        #expect(InsightsView.isHourlyEmpty(todayHourCounts: [:], dailyActivity: activity) == false)
    }

    // DATA-01: all-zero hourCounts + today has daily activity → loading, not empty
    @Test func isHourlyEmpty_allZeroHourCounts_withTodayActivity_returnsFalse() {
        let activity = [DailyActivity(date: todayKey, messageCount: 3, sessionCount: 1, toolCallCount: 0)]
        let counts: [String: Int] = ["10": 0, "11": 0, "12": 0]
        #expect(InsightsView.isHourlyEmpty(todayHourCounts: counts, dailyActivity: activity) == false)
    }

    // DATA-01: no daily activity at all → genuinely empty
    @Test func isHourlyEmpty_noActivity_returnsTrue() {
        #expect(InsightsView.isHourlyEmpty(todayHourCounts: [:], dailyActivity: []) == true)
    }

    // DATA-01: only prior-day activity → today is genuinely empty (not a loading signal)
    @Test func isHourlyEmpty_onlyYesterdayActivity_returnsTrue() {
        let activity = [DailyActivity(date: yesterdayKey, messageCount: 5, sessionCount: 1, toolCallCount: 0)]
        #expect(InsightsView.isHourlyEmpty(todayHourCounts: [:], dailyActivity: activity) == true)
    }
}
