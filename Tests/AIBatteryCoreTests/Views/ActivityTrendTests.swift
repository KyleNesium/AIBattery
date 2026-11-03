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

    /// Regression: a trivially small `previous` value (e.g. 100 tokens from a
    /// background hook fire over a weekend) used to produce absurd percentages
    /// like `+47999% vs yesterday`. Now suppressed entirely when previous is
    /// below the meaningful threshold (1000 tokens) — the user reads the
    /// absolute numbers in the chart, the noise comparison is gone.
    @Test func changeVsYesterday_belowMeaningfulThreshold_returnsNil() throws {
        let cal = Calendar.current
        let now = Date()
        let todayStr = DateFormatters.dateKey.string(from: now)
        let yesterdayStr = try DateFormatters.dateKey.string(from: #require(cal.date(byAdding: .day, value: -1, to: now)))
        let snapshot = makeSnapshot(dailyTokenTotals: [todayStr: 50_000, yesterdayStr: 100])
        let change = ActivityTrendComputation.changeVsYesterday(snapshot, cal: cal, now: now)
        #expect(change == nil)
    }

    /// Yesterday exactly at the threshold still produces a percentage —
    /// the threshold is inclusive so the boundary case is well-defined.
    @Test func changeVsYesterday_atMeaningfulThreshold_returnsPercent() throws {
        let cal = Calendar.current
        let now = Date()
        let todayStr = DateFormatters.dateKey.string(from: now)
        let yesterdayStr = try DateFormatters.dateKey.string(from: #require(cal.date(byAdding: .day, value: -1, to: now)))
        let snapshot = makeSnapshot(dailyTokenTotals: [todayStr: 1_500, yesterdayStr: 1_000])
        let change = ActivityTrendComputation.changeVsYesterday(snapshot, cal: cal, now: now)
        #expect(change?.symbol == "↑")
        #expect(change?.label == "+50% vs yesterday")
    }

    /// Percentages above 999% display as `>999%` rather than the raw multi-digit
    /// figure — keeps the trend row readable when previous is just above the
    /// threshold and current is enormous.
    @Test func changeVsYesterday_extremeSpike_capsAt999() throws {
        let cal = Calendar.current
        let now = Date()
        let todayStr = DateFormatters.dateKey.string(from: now)
        let yesterdayStr = try DateFormatters.dateKey.string(from: #require(cal.date(byAdding: .day, value: -1, to: now)))
        // Yesterday is 6% of today: above the relative threshold, so a real (huge) spike.
        let snapshot = makeSnapshot(dailyTokenTotals: [todayStr: 500_000, yesterdayStr: 30_000])
        let change = ActivityTrendComputation.changeVsYesterday(snapshot, cal: cal, now: now)
        #expect(change?.symbol == "↑")
        #expect(change?.label == ">999% vs yesterday")
    }

    /// The threshold is relative, not a fixed token count: 1 000 tokens is 0.003% of a
    /// 30M-token day, so a stray hook session used to clear the old fixed floor and
    /// print ">999% vs yesterday" instead of being suppressed.
    @Test func changeVsYesterday_relativeThreshold_suppressesStrayPreviousDay() throws {
        let cal = Calendar.current
        let now = Date()
        let todayStr = DateFormatters.dateKey.string(from: now)
        let yesterdayStr = try DateFormatters.dateKey.string(from: #require(cal.date(byAdding: .day, value: -1, to: now)))
        let snapshot = makeSnapshot(dailyTokenTotals: [todayStr: 30_000_000, yesterdayStr: 5_000])
        #expect(ActivityTrendComputation.changeVsYesterday(snapshot, cal: cal, now: now) == nil)

        // The absolute floor still applies to small volumes.
        #expect(ActivityTrendComputation.meaningfulPreviousThreshold(current: 100) == 1_000)
        #expect(ActivityTrendComputation.meaningfulPreviousThreshold(current: 30_000_000) == 1_500_000)
    }

    // MARK: - monthChangeInfo

    @Test func monthChange_positiveProjection() throws {
        let cal = Calendar.current
        // March 15, 2026 — dayOfMonth=15, daysInMonth=31
        let now = try #require(cal.date(from: DateComponents(year: 2_026, month: 3, day: 15)))
        // thisMonth=100_000, projected=100_000*31/15=206_666, lastMonth=100_000 → +107% → ↑
        // Token totals above `meaningfulPreviousThreshold` so the trend renders.
        let change = ActivityTrendComputation.monthChangeInfo(thisMonth: 100_000, lastMonth: 100_000, cal: cal, now: now)
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
            change: ActivityChangeInfo(direction: .up, label: "+5 vs yesterday", color: .orange),
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

    // MARK: - 12-month window

    /// The chart plots exactly the rolling twelve months, but the summary beneath it
    /// used to reduce every month the aggregator had ever written. Anyone retaining more
    /// than a year of logs saw "N in 12m" and "Peak" disagree with the chart above them.
    @Test func monthlyStatAndPeakUseOnlyTheRollingTwelveMonths() throws {
        let keys = ActivityChartData.rollingTwelveMonthKeys()
        #expect(keys.count == 12)

        var totals: [String: Int] = [:]
        for key in keys {
            totals[key] = 1_000
        }
        // An ancient month, far larger than anything in the window.
        let cal = Calendar.current
        let ancient = try #require(cal.date(byAdding: .month, value: -30, to: Date()))
        let comps = cal.dateComponents([.year, .month], from: ancient)
        let ancientKey = try String(format: "%04d-%02d", #require(comps.year), #require(comps.month))
        totals[ancientKey] = 10_000_000

        let data = ActivityTrendComputation.compute(
            mode: .monthly,
            snapshot: makeSnapshot(),
            monthTotals: totals
        )

        // 12 × 1,000 = 12,000 exactly. Compare against the formatter's own output so the
        // assertion cannot be satisfied by an unrelated "12" elsewhere in the string —
        // "in 12m" is part of every value this can take.
        let stat = try #require(data.stat)
        #expect(stat == "\(InsightsView.compactCount(12_000)) in 12m", "stat was \(stat)")

        // And it must not win "Peak" either.
        let ancientAbbrev = InsightsView.monthAbbrev(ancient)
        #expect(data.peak != "Peak: \(ancientAbbrev)", "an out-of-window month was named the peak")
    }

    @Test func rollingTwelveMonthKeysEndOnTheCurrentMonthAndAreAscending() {
        let keys = ActivityChartData.rollingTwelveMonthKeys()
        #expect(keys == keys.sorted(), "keys must be oldest first")
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: Date())
        if let y = comps.year, let m = comps.month {
            #expect(keys.last == String(format: "%04d-%02d", y, m))
        }
    }

    private func makeSnapshot(
        todayMessages: Int = 0,
        dailyActivity: [DailyActivity] = [],
        dailyTokenTotals: [String: Int] = [:]
    ) -> UsageSnapshot {
        let busiestDay = UsageSnapshot.computeBusiestDay(dailyActivity)
        return UsageSnapshot(
            lastUpdated: Date(),
            rateLimits: nil,
            rateLimitSource: nil,
            standardLimits: nil,
            rateLimitsFresh: true,
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
            busiestDayOfWeek: busiestDay,
            hourCounts: [:],
            todayHourCounts: [:],
            tokenHealth: nil,
            topSessionHealths: []
        )
    }
}
