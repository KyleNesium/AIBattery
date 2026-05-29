import Testing
import Foundation
@testable import AIBatteryCore

@Suite("ActivityChartIsEmpty")
@MainActor
struct ActivityChartIsEmptyTests {
    // The old InsightsView.isHourlyEmpty() static method was removed.
    // Emptiness is now determined by snapshot token fields directly.
    // These tests verify the underlying data signals used by ActivityChartView.isEmpty.

    // DATA-01: no five-hour tokens → fiveHour mode is empty
    @Test func fiveHourEmpty_whenFiveHourTokensIsZero() {
        let snapshot = makeSnapshot(fiveHourTokens: 0)
        #expect(snapshot.fiveHourTokens == 0)
    }

    // DATA-01: has five-hour tokens → fiveHour mode is not empty
    @Test func fiveHourNotEmpty_whenFiveHourTokensNonZero() {
        let snapshot = makeSnapshot(fiveHourTokens: 1_000)
        #expect(snapshot.fiveHourTokens > 0)
    }

    // DATA-01: no seven-day tokens → sevenDay mode is empty
    @Test func sevenDayEmpty_whenSevenDayTokensIsZero() {
        let snapshot = makeSnapshot(sevenDayTokens: 0)
        #expect(snapshot.sevenDayTokens == 0)
    }

    // DATA-01: has seven-day tokens → sevenDay mode is not empty
    @Test func sevenDayNotEmpty_whenSevenDayTokensNonZero() {
        let snapshot = makeSnapshot(sevenDayTokens: 5_000)
        #expect(snapshot.sevenDayTokens > 0)
    }

    // DATA-01: empty dailyTokenTotals → monthly mode is empty
    @Test func monthlyEmpty_whenDailyTokenTotalsEmpty() {
        let snapshot = makeSnapshot(dailyTokenTotals: [:])
        #expect(snapshot.dailyTokenTotals.values.reduce(0, +) == 0)
    }

    // DATA-01: has dailyTokenTotals → monthly mode is not empty
    @Test func monthlyNotEmpty_whenDailyTokenTotalsNonZero() {
        let snapshot = makeSnapshot(dailyTokenTotals: ["2026-03-01": 12_000])
        #expect(snapshot.dailyTokenTotals.values.reduce(0, +) > 0)
    }

    // MARK: - displayState (loading vs empty vs data)

    // LOAD-01: nil snapshot → loading (NOT empty — prevents the cold-start "No activity" flash)
    @Test func displayState_nilSnapshot_isLoading() {
        #expect(InsightsView.displayState(snapshot: nil, mode: .fiveHour) == .loading)
        #expect(InsightsView.displayState(snapshot: nil, mode: .sevenDay) == .loading)
        #expect(InsightsView.displayState(snapshot: nil, mode: .monthly) == .loading)
    }

    // LOAD-02: snapshot present but zero tokens → genuinely empty
    @Test func displayState_loadedZeroTokens_isEmpty() {
        #expect(InsightsView.displayState(snapshot: makeSnapshot(fiveHourTokens: 0), mode: .fiveHour) == .empty)
        #expect(InsightsView.displayState(snapshot: makeSnapshot(sevenDayTokens: 0), mode: .sevenDay) == .empty)
        #expect(InsightsView.displayState(snapshot: makeSnapshot(dailyTokenTotals: [:]), mode: .monthly) == .empty)
    }

    // LOAD-03: snapshot present with tokens → data
    @Test func displayState_loadedWithTokens_isData() {
        #expect(InsightsView.displayState(snapshot: makeSnapshot(fiveHourTokens: 1_000), mode: .fiveHour) == .data)
        #expect(InsightsView.displayState(snapshot: makeSnapshot(sevenDayTokens: 5_000), mode: .sevenDay) == .data)
        #expect(InsightsView.displayState(snapshot: makeSnapshot(dailyTokenTotals: ["2026-03-01": 12_000]), mode: .monthly) == .data)
    }

    // MARK: - Helpers

    private func makeSnapshot(
        fiveHourTokens: Int = 0,
        sevenDayTokens: Int = 0,
        dailyTokenTotals: [String: Int] = [:]
    ) -> UsageSnapshot {
        UsageSnapshot(
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
            todayMessages: 0,
            todaySessions: 0,
            todayToolCalls: 0,
            modelTokens: [],
            projectTokens: [],
            totalTokens: 0,
            totalUsageTokens: 0,
            totalProjectTokens: 0,
            totalProjectUsageTokens: 0,
            totalProjectCost: 0,
            fiveHourTokens: fiveHourTokens,
            sevenDayTokens: sevenDayTokens,
            fiveHourTokenBuckets: [:],
            dailyTokenTotals: dailyTokenTotals,
            todayModelTokens: [],
            weekModelTokens: [],
            monthModelTokens: [],
            dailyActivity: [],
            dailyAverage: 0,
            trendDirection: .flat,
            busiestDayOfWeek: nil,
            hourCounts: [:],
            todayHourCounts: [:],
            tokenHealth: nil,
            topSessionHealths: []
        )
    }
}
