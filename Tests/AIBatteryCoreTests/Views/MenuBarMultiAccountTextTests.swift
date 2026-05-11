import Testing
import Foundation
@testable import AIBatteryCore

@Suite("MenuBarMultiAccountText")
struct MenuBarMultiAccountTextTests {
    // MARK: - Helpers

    private static func usage(
        fiveHourUtilization: Double = 0,
        sevenDayUtilization: Double = 0,
        fiveHourReset: Date? = nil,
        sevenDayReset: Date? = nil,
        fiveHourStatus: String = "allowed",
        sevenDayStatus: String = "allowed",
        overallStatus: String = "allowed",
        representativeClaim: String = RateLimitUsage.fiveHourWindow
    ) -> RateLimitUsage {
        RateLimitUsage(
            representativeClaim: representativeClaim,
            fiveHourUtilization: fiveHourUtilization,
            fiveHourReset: fiveHourReset,
            fiveHourStatus: fiveHourStatus,
            sevenDayUtilization: sevenDayUtilization,
            sevenDayReset: sevenDayReset,
            sevenDayStatus: sevenDayStatus,
            overallStatus: overallStatus
        )
    }

    // MARK: - Format basics

    @Test("Two accounts: text uses non-breaking-space-padded separator")
    func twoAccountsFormat() {
        let limits: [String: RateLimitUsage] = [
            "a": Self.usage(fiveHourUtilization: 0.42),
            "b": Self.usage(fiveHourUtilization: 0.23),
        ]
        let out = MenuBarMultiAccountText.build(order: ["a", "b"], limits: limits, metricMode: .fiveHour)
        #expect(out.text == "42%\u{00A0}|\u{00A0}23%")
    }

    @Test("Three accounts: emits three slots with two separators")
    func threeAccountsFormat() {
        let limits: [String: RateLimitUsage] = [
            "a": Self.usage(fiveHourUtilization: 0.42),
            "b": Self.usage(fiveHourUtilization: 0.23),
            "c": Self.usage(fiveHourUtilization: 0.99),
        ]
        let out = MenuBarMultiAccountText.build(order: ["a", "b", "c"], limits: limits, metricMode: .fiveHour)
        #expect(out.text == "42%\u{00A0}|\u{00A0}23%\u{00A0}|\u{00A0}99%")
    }

    @Test("Order follows the order array, not max-first")
    func orderRespected() {
        let limits: [String: RateLimitUsage] = [
            "a": Self.usage(fiveHourUtilization: 0.10),
            "b": Self.usage(fiveHourUtilization: 0.90),
        ]
        let outAB = MenuBarMultiAccountText.build(order: ["a", "b"], limits: limits, metricMode: .fiveHour)
        let outBA = MenuBarMultiAccountText.build(order: ["b", "a"], limits: limits, metricMode: .fiveHour)
        #expect(outAB.text == "10%\u{00A0}|\u{00A0}90%")
        #expect(outBA.text == "90%\u{00A0}|\u{00A0}10%")
    }

    // MARK: - Missing data

    @Test("Missing entry renders as em-dash slot")
    func missingEntryRendersDash() {
        let limits: [String: RateLimitUsage] = [
            "a": Self.usage(fiveHourUtilization: 0.42),
            // "b" missing
        ]
        let out = MenuBarMultiAccountText.build(order: ["a", "b"], limits: limits, metricMode: .fiveHour)
        #expect(out.text == "42%\u{00A0}|\u{00A0}—")
    }

    @Test("All slots missing: renders em-dashes, doesn't crash")
    func allMissingRendersDashes() {
        let out = MenuBarMultiAccountText.build(order: ["a", "b"], limits: [:], metricMode: .fiveHour)
        #expect(out.text == "—\u{00A0}|\u{00A0}—")
        #expect(out.worstPercent == 0)
        #expect(out.anyThrottled == false)
    }

    // MARK: - Single-account safety

    @Test("Single account: builder produces text without separator")
    func singleAccountNoSeparator() {
        let limits: [String: RateLimitUsage] = [
            "a": Self.usage(fiveHourUtilization: 0.42),
        ]
        let out = MenuBarMultiAccountText.build(order: ["a"], limits: limits, metricMode: .fiveHour)
        #expect(out.text == "42%")
        #expect(!out.text.contains("|"))
    }

    // MARK: - Worst-percent

    @Test("WorstPercent is max across all slots")
    func worstPercentIsMax() {
        let limits: [String: RateLimitUsage] = [
            "a": Self.usage(fiveHourUtilization: 0.12),
            "b": Self.usage(fiveHourUtilization: 0.87),
            "c": Self.usage(fiveHourUtilization: 0.45),
        ]
        let out = MenuBarMultiAccountText.build(order: ["a", "b", "c"], limits: limits, metricMode: .fiveHour)
        #expect(out.worstPercent == 87)
    }

    @Test("WorstPercent is 0 when limits is empty")
    func worstPercentEmpty() {
        let out = MenuBarMultiAccountText.build(order: [], limits: [:], metricMode: .fiveHour)
        #expect(out.worstPercent == 0)
    }

    // MARK: - Throttled detection

    @Test("AnyThrottled is false when all are allowed")
    func anyThrottledFalse() {
        let limits: [String: RateLimitUsage] = [
            "a": Self.usage(fiveHourUtilization: 0.20),
            "b": Self.usage(fiveHourUtilization: 0.30),
        ]
        let out = MenuBarMultiAccountText.build(order: ["a", "b"], limits: limits, metricMode: .fiveHour)
        #expect(out.anyThrottled == false)
    }

    @Test("AnyThrottled is true when any account has overallStatus throttled")
    func anyThrottledTrueViaOverall() {
        let limits: [String: RateLimitUsage] = [
            "a": Self.usage(fiveHourUtilization: 0.20),
            "b": Self.usage(fiveHourUtilization: 0.30, overallStatus: "throttled"),
        ]
        let out = MenuBarMultiAccountText.build(order: ["a", "b"], limits: limits, metricMode: .fiveHour)
        #expect(out.anyThrottled == true)
    }

    @Test("AnyThrottled is true when any window hits 100% even without explicit status")
    func anyThrottledTrueVia100Percent() {
        let limits: [String: RateLimitUsage] = [
            "a": Self.usage(fiveHourUtilization: 0.20),
            "b": Self.usage(fiveHourUtilization: 1.0),
        ]
        let out = MenuBarMultiAccountText.build(order: ["a", "b"], limits: limits, metricMode: .fiveHour)
        #expect(out.anyThrottled == true)
    }

    // MARK: - MetricMode

    @Test("MetricMode .fiveHour reads fiveHourPercent")
    func fiveHourMode() {
        let limits: [String: RateLimitUsage] = [
            "a": Self.usage(fiveHourUtilization: 0.42, sevenDayUtilization: 0.99),
        ]
        let out = MenuBarMultiAccountText.build(order: ["a"], limits: limits, metricMode: .fiveHour)
        #expect(out.text == "42%")
    }

    @Test("MetricMode .sevenDay reads sevenDayPercent")
    func sevenDayMode() {
        let limits: [String: RateLimitUsage] = [
            "a": Self.usage(fiveHourUtilization: 0.42, sevenDayUtilization: 0.99),
        ]
        let out = MenuBarMultiAccountText.build(order: ["a"], limits: limits, metricMode: .sevenDay)
        #expect(out.text == "99%")
    }

    @Test("MetricMode .contextHealth falls back to fiveHourPercent")
    func contextHealthFallsBackToFiveHour() {
        let limits: [String: RateLimitUsage] = [
            "a": Self.usage(fiveHourUtilization: 0.42, sevenDayUtilization: 0.99),
        ]
        let out = MenuBarMultiAccountText.build(order: ["a"], limits: limits, metricMode: .contextHealth)
        #expect(out.text == "42%")
    }

    // MARK: - Rounding

    @Test("Percent rounds to nearest integer")
    func percentRoundsToNearest() {
        let lower: [String: RateLimitUsage] = ["a": Self.usage(fiveHourUtilization: 0.424)]
        let upper: [String: RateLimitUsage] = ["a": Self.usage(fiveHourUtilization: 0.426)]
        #expect(MenuBarMultiAccountText.build(order: ["a"], limits: lower, metricMode: .fiveHour).text == "42%")
        #expect(MenuBarMultiAccountText.build(order: ["a"], limits: upper, metricMode: .fiveHour).text == "43%")
    }

    // MARK: - shouldRender gate

    @Test("shouldRender is false when toggle is off, regardless of account count")
    func shouldRenderOffWhenToggleOff() {
        #expect(MenuBarMultiAccountText.shouldRender(toggleOn: false, fetchedAccountCount: 0) == false)
        #expect(MenuBarMultiAccountText.shouldRender(toggleOn: false, fetchedAccountCount: 1) == false)
        #expect(MenuBarMultiAccountText.shouldRender(toggleOn: false, fetchedAccountCount: 2) == false)
        #expect(MenuBarMultiAccountText.shouldRender(toggleOn: false, fetchedAccountCount: 3) == false)
    }

    @Test("shouldRender requires ≥2 accounts when toggle is on")
    func shouldRenderRequiresTwoAccounts() {
        #expect(MenuBarMultiAccountText.shouldRender(toggleOn: true, fetchedAccountCount: 0) == false)
        #expect(MenuBarMultiAccountText.shouldRender(toggleOn: true, fetchedAccountCount: 1) == false)
        #expect(MenuBarMultiAccountText.shouldRender(toggleOn: true, fetchedAccountCount: 2) == true)
        #expect(MenuBarMultiAccountText.shouldRender(toggleOn: true, fetchedAccountCount: 3) == true)
    }

    @Test("v2.2.0 regression: empty perAccount must NOT trigger multi-account render")
    func shouldRender_emptyPerAccount_doesNotRender_v220Regression() {
        // v2.2.0 shipped with the call site gating on
        // `accountStore.accounts.count` (authenticated count) rather than
        // `perAccountRateLimits.count` (count with data). On first launch with
        // the toggle on, perAccount is empty for the brief window between
        // toggle observation and fan-out completion — and the menu bar rendered
        // "— | —" indefinitely for users whose fan-out failed entirely
        // (transient auth, no network on launch).
        //
        // Pin the contract: when *no* accounts have fetched data, the predicate
        // must return false so callers fall back to the single-account renderer
        // which reads `snapshot.rateLimits` directly and shows the real percent.
        let perAccount: [String: RateLimitUsage] = [:]
        #expect(MenuBarMultiAccountText.shouldRender(toggleOn: true, fetchedAccountCount: perAccount.count) == false)
    }

    @Test("v2.2.0 regression: only 1 fetched does NOT trigger multi-account render")
    func shouldRender_onlyOneFetched_doesNotRender_v220Regression() {
        // Same v2.2.0 failure mode for the partial-fan-out case: 2 authenticated
        // accounts but only 1 returned rate-limit data. Old buggy gate would
        // render "X% | —". v2.2.1 gate falls back to single-account which shows
        // the active account's real percent — strictly better UX than a half-
        // populated multi-account strip.
        let perAccount: [String: RateLimitUsage] = [
            "account-a": Self.usage(fiveHourUtilization: 0.42),
        ]
        #expect(MenuBarMultiAccountText.shouldRender(toggleOn: true, fetchedAccountCount: perAccount.count) == false)
    }

    // Note: per-account countdown selection lives in `StatusBarManager.countdownResetDate`
    // and is covered by `StatusBarCountdownResetDateTests`. The multi-account branch
    // composes that helper via `.compactMap { ... }.min()`, which only emits a date
    // when an account is actually exhausted — healthy future resets never pin the menu
    // bar into countdown mode.
}
