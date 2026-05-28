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

    @Test("AnyThrottled is FALSE at 100% without an explicit throttled status (at-capacity, not throttled)")
    func anyThrottledFalseVia100PercentWithoutStatus() {
        let limits: [String: RateLimitUsage] = [
            "a": Self.usage(fiveHourUtilization: 0.20),
            "b": Self.usage(fiveHourUtilization: 1.0),
        ]
        let out = MenuBarMultiAccountText.build(order: ["a", "b"], limits: limits, metricMode: .fiveHour)
        #expect(out.anyThrottled == false)
    }

    @Test("AnyThrottled is true at 100% WITH an explicit throttled status")
    func anyThrottledTrueVia100PercentWithStatus() {
        let limits: [String: RateLimitUsage] = [
            "a": Self.usage(fiveHourUtilization: 0.20),
            "b": Self.usage(fiveHourUtilization: 1.0, fiveHourStatus: "throttled", overallStatus: "throttled"),
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

    // MARK: - resolveDisplay end-to-end

    //
    // These tests exercise the full menu-bar decision (gate + builder + countdown
    // composition + single-account fallback) as one pure function. They are the
    // safety net that should have caught the v2.2.0 "— | —" regression.

    /// Stub countdown resolver matching `StatusBarManager.countdownResetDate(for:now:)`
    /// semantics: returns nil for healthy accounts, the binding reset (if future) for
    /// throttled, or the future-exhausted-window reset otherwise.
    private static func countdownReset(_ usage: RateLimitUsage, _ now: Date) -> Date? {
        let future: (Date?) -> Date? = { d in
            guard let d, d.timeIntervalSince(now) > 0 else { return nil }
            return d
        }
        if usage.isThrottled { return future(usage.bindingReset) }
        let fiveExhausted = usage.fiveHourPercent >= 100
        let sevenExhausted = usage.sevenDayPercent >= 100
        let f = fiveExhausted ? future(usage.fiveHourReset) : nil
        let s = sevenExhausted ? future(usage.sevenDayReset) : nil
        return [f, s].compactMap { $0 }.min()
    }

    @Test("Single account toggle off: renders active percent, no multi branch")
    func resolveDisplay_singleAccount_toggleOff() {
        let active = Self.usage(fiveHourUtilization: 0.42)
        let result = MenuBarMultiAccountText.resolveDisplay(
            toggleOn: false,
            perAccount: [:],
            order: ["a"],
            activeRateLimits: active,
            activePercent: 42,
            metricMode: .fiveHour,
            now: Date(),
            countdownResetDate: Self.countdownReset
        )
        #expect(result.usedMultiAccount == false)
        #expect(result.text == "42%")
        #expect(result.percent == 42)
        #expect(result.isExhausted == false)
        #expect(result.countdownReset == nil)
    }

    @Test("v2.2.0 regression: toggle on, 2 authenticated, empty perAccount → single fallback (NOT '— | —')")
    func resolveDisplay_v220Regression_emptyPerAccount() {
        let active = Self.usage(fiveHourUtilization: 0.42)
        let result = MenuBarMultiAccountText.resolveDisplay(
            toggleOn: true,
            perAccount: [:], // fan-out hasn't completed yet
            order: ["a", "b"], // 2 authenticated accounts
            activeRateLimits: active,
            activePercent: 42,
            metricMode: .fiveHour,
            now: Date(),
            countdownResetDate: Self.countdownReset
        )
        // v2.2.0 shipped "— | —" here because the gate used order.count.
        // v2.2.1 fix: gate on perAccount.count, so empty map → single-account
        // fallback shows active percent.
        #expect(result.usedMultiAccount == false)
        #expect(result.text == "42%")
        #expect(!result.text.contains("—"))
        #expect(!result.text.contains("|"))
    }

    @Test("v2.2.0 regression: toggle on, only 1 fetched → single fallback (NOT 'X% | —')")
    func resolveDisplay_v220Regression_onlyOneFetched() {
        let active = Self.usage(fiveHourUtilization: 0.42)
        let result = MenuBarMultiAccountText.resolveDisplay(
            toggleOn: true,
            perAccount: ["a": active], // only 1 fetched
            order: ["a", "b"],
            activeRateLimits: active,
            activePercent: 42,
            metricMode: .fiveHour,
            now: Date(),
            countdownResetDate: Self.countdownReset
        )
        #expect(result.usedMultiAccount == false)
        #expect(result.text == "42%")
    }

    @Test("Toggle on, 2 fetched: renders 'X% | Y%' with worst-percent driving icon")
    func resolveDisplay_twoFetched_rendersMulti() {
        let a = Self.usage(fiveHourUtilization: 0.42)
        let b = Self.usage(fiveHourUtilization: 0.87)
        let result = MenuBarMultiAccountText.resolveDisplay(
            toggleOn: true,
            perAccount: ["a": a, "b": b],
            order: ["a", "b"],
            activeRateLimits: a,
            activePercent: 42,
            metricMode: .fiveHour,
            now: Date(),
            countdownResetDate: Self.countdownReset
        )
        #expect(result.usedMultiAccount == true)
        #expect(result.text == "42%\u{00A0}|\u{00A0}87%")
        #expect(result.percent == 87) // worst across accounts
        #expect(result.isExhausted == false)
    }

    @Test("Toggle on, 3 fetched: all three slots render in order")
    func resolveDisplay_threeFetched_rendersMulti() {
        let a = Self.usage(fiveHourUtilization: 0.10)
        let b = Self.usage(fiveHourUtilization: 0.50)
        let c = Self.usage(fiveHourUtilization: 0.90)
        let result = MenuBarMultiAccountText.resolveDisplay(
            toggleOn: true,
            perAccount: ["a": a, "b": b, "c": c],
            order: ["a", "b", "c"],
            activeRateLimits: a,
            activePercent: 10,
            metricMode: .fiveHour,
            now: Date(),
            countdownResetDate: Self.countdownReset
        )
        #expect(result.usedMultiAccount == true)
        #expect(result.text == "10%\u{00A0}|\u{00A0}50%\u{00A0}|\u{00A0}90%")
        #expect(result.percent == 90)
    }

    @Test("Multi-account: healthy accounts do NOT trigger countdown (P1 regression pin)")
    func resolveDisplay_healthyAccounts_noCountdown() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        // Healthy: low utilization, future reset, not throttled.
        let a = Self.usage(fiveHourUtilization: 0.42, fiveHourReset: now.addingTimeInterval(3_600))
        let b = Self.usage(fiveHourUtilization: 0.23, fiveHourReset: now.addingTimeInterval(3_600))
        let result = MenuBarMultiAccountText.resolveDisplay(
            toggleOn: true,
            perAccount: ["a": a, "b": b],
            order: ["a", "b"],
            activeRateLimits: a,
            activePercent: 42,
            metricMode: .fiveHour,
            now: now,
            countdownResetDate: Self.countdownReset
        )
        #expect(result.usedMultiAccount == true)
        #expect(result.countdownReset == nil)
        // Should render percent strip, NOT a countdown like "1h 0m"
        #expect(result.text == "42%\u{00A0}|\u{00A0}23%")
    }

    @Test("Multi-account: one account throttled → countdown mode kicks in")
    func resolveDisplay_oneThrottled_countdown() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let reset = now.addingTimeInterval(300) // 5 min away
        let a = Self.usage(fiveHourUtilization: 0.42)
        let throttled = Self.usage(
            fiveHourUtilization: 1.0,
            fiveHourReset: reset,
            fiveHourStatus: "throttled",
            overallStatus: "throttled"
        )
        let result = MenuBarMultiAccountText.resolveDisplay(
            toggleOn: true,
            perAccount: ["a": a, "b": throttled],
            order: ["a", "b"],
            activeRateLimits: a,
            activePercent: 42,
            metricMode: .fiveHour,
            now: now,
            countdownResetDate: Self.countdownReset
        )
        #expect(result.usedMultiAccount == true)
        #expect(result.countdownReset == reset)
        #expect(result.isExhausted == true)
        // Countdown text — not the percent strip — when an account is exhausted.
        #expect(result.text != "42%\u{00A0}|\u{00A0}100%")
    }

    @Test("Single-account: active throttled → countdown mode")
    func resolveDisplay_singleAccount_throttled_countdown() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let reset = now.addingTimeInterval(120)
        let throttled = Self.usage(
            fiveHourUtilization: 1.0,
            fiveHourReset: reset,
            fiveHourStatus: "throttled",
            overallStatus: "throttled"
        )
        let result = MenuBarMultiAccountText.resolveDisplay(
            toggleOn: false,
            perAccount: [:],
            order: ["a"],
            activeRateLimits: throttled,
            activePercent: 100,
            metricMode: .fiveHour,
            now: now,
            countdownResetDate: Self.countdownReset
        )
        #expect(result.usedMultiAccount == false)
        #expect(result.countdownReset == reset)
        #expect(result.isExhausted == true)
        // Binding window code prefixed so the menu bar says which window (5h here).
        #expect(result.text.hasPrefix("5H "))
    }

    @Test("Single-account: 7-day throttle prefixes the 7D window code")
    func resolveDisplay_singleAccount_sevenDayThrottle_prefixesCode() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let reset = now.addingTimeInterval(3_600)
        let throttled = Self.usage(
            sevenDayUtilization: 1.0,
            sevenDayReset: reset,
            sevenDayStatus: "throttled",
            overallStatus: "throttled",
            representativeClaim: RateLimitUsage.sevenDayWindow
        )
        let result = MenuBarMultiAccountText.resolveDisplay(
            toggleOn: false,
            perAccount: [:],
            order: ["a"],
            activeRateLimits: throttled,
            activePercent: 100,
            metricMode: .sevenDay,
            now: now,
            countdownResetDate: Self.countdownReset
        )
        #expect(result.text.hasPrefix("7D "))
    }

    @Test("Single-account: NOT throttled (at 100%) does not prefix a window code")
    func resolveDisplay_singleAccount_atCapacityNotThrottled_noPrefix() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let reset = now.addingTimeInterval(120)
        // 100% utilization but allowed — at capacity, not throttled.
        let atCapacity = Self.usage(
            fiveHourUtilization: 1.0,
            fiveHourReset: reset,
            fiveHourStatus: "allowed",
            overallStatus: "allowed"
        )
        let result = MenuBarMultiAccountText.resolveDisplay(
            toggleOn: false,
            perAccount: [:],
            order: ["a"],
            activeRateLimits: atCapacity,
            activePercent: 100,
            metricMode: .fiveHour,
            now: now,
            countdownResetDate: Self.countdownReset
        )
        #expect(!result.text.hasPrefix("5H "))
        #expect(!result.text.hasPrefix("7D "))
    }

    @Test("Multi-account: worst-percent floored at active so icon never shrinks")
    func resolveDisplay_worstPercentFlooredAtActive() {
        // Active has higher percent than any other account — multi.worstPercent < activePercent.
        let active = Self.usage(fiveHourUtilization: 0.85)
        let other = Self.usage(fiveHourUtilization: 0.20)
        let result = MenuBarMultiAccountText.resolveDisplay(
            toggleOn: true,
            perAccount: ["active": active, "other": other],
            order: ["active", "other"],
            activeRateLimits: active,
            activePercent: 85,
            metricMode: .fiveHour,
            now: Date(),
            countdownResetDate: Self.countdownReset
        )
        #expect(result.usedMultiAccount == true)
        #expect(result.percent == 85) // floor at active, not the multi.worstPercent of 85
    }

    @Test("Toggle on, 1 authenticated account: shouldRender false, single-account fallback")
    func resolveDisplay_toggleOnSingleAccount_fallback() {
        // Edge case: user enables toggle but only has 1 account connected.
        let a = Self.usage(fiveHourUtilization: 0.42)
        let result = MenuBarMultiAccountText.resolveDisplay(
            toggleOn: true,
            perAccount: ["a": a],
            order: ["a"],
            activeRateLimits: a,
            activePercent: 42,
            metricMode: .fiveHour,
            now: Date(),
            countdownResetDate: Self.countdownReset
        )
        #expect(result.usedMultiAccount == false)
        #expect(result.text == "42%")
    }
}
