import Foundation

/// Pure text builder for the multi-account menu bar display.
/// No AppKit / SwiftUI dependency — fully unit-testable from outside the MainActor.
///
/// Activated when `aibattery_showAllAccountsInMenuBar == true` AND ≥2 authenticated
/// accounts are present. Renders each account's percent in `AccountStore.accounts`
/// order, joined by non-breaking-space-padded `|` so a slot doesn't break across the
/// separator. The icon visuals (star color, breath, broken state) are driven by the
/// **worst** account, since one icon must communicate the most actionable signal.
enum MenuBarMultiAccountText {
    struct Output: Equatable {
        /// e.g. "42%\u{00A0}|\u{00A0}23%". Empty for empty input.
        let text: String
        /// Worst (max) percent across all known accounts; 0 if none have data.
        /// Drives star color and breathing intensity.
        let worstPercent: Double
        /// True if any account is currently throttled or any window hits 100%.
        /// Drives the broken-star state.
        let anyThrottled: Bool
    }

    /// Non-breaking spaces around the `|` so the slot text doesn't break across the
    /// separator and so menu-bar layout treats each `xx%` as a unit.
    static let separator = "\u{00A0}|\u{00A0}"

    /// Build the menu bar text + visual signals for a multi-account display.
    ///
    /// - Parameters:
    ///   - order: account IDs in display order (typically `AccountStore.accounts.map(\.id)`).
    ///   - limits: per-account `RateLimitUsage`, keyed by account ID. Missing entries → "—".
    ///   - metricMode: the active metric mode. `.contextHealth` falls back to `.fiveHour`
    ///     because context health is per-session, not per-account, and would not
    ///     produce a meaningful per-account number.
    static func build(
        order: [String],
        limits: [String: RateLimitUsage],
        metricMode: MetricMode
    ) -> Output {
        let resolvedMode: MetricMode = (metricMode == .contextHealth) ? .fiveHour : metricMode
        let parts: [String] = order.map { id in
            guard let usage = limits[id] else { return "—" }
            let pct = percent(for: usage, mode: resolvedMode)
            return "\(Int(pct.rounded()))%"
        }
        let text = parts.joined(separator: separator)
        let worstPercent = limits.values
            .map { percent(for: $0, mode: resolvedMode) }
            .max() ?? 0
        let anyThrottled = limits.values.contains { isExhausted($0) }
        return Output(text: text, worstPercent: worstPercent, anyThrottled: anyThrottled)
    }

    /// Whether the toggle would render a multi-account display given current state.
    ///
    /// - Parameter fetchedAccountCount: count of accounts with **fetched rate-limit
    ///   data** (i.e. `UsageViewModel.perAccountRateLimits.count`), NOT the count of
    ///   authenticated accounts. v2.2.0 shipped a regression where the call site
    ///   passed `accountStore.accounts.count`, which fired the multi-account branch
    ///   before the fan-out had populated any data, rendering "— | —" indefinitely
    ///   on first launch. The fallback when fewer than 2 accounts have data is the
    ///   single-account renderer (uses `snapshot.rateLimits` directly), so the user
    ///   always sees the active account's real percent in that transient window.
    static func shouldRender(
        toggleOn: Bool,
        fetchedAccountCount: Int
    ) -> Bool {
        toggleOn && fetchedAccountCount >= 2
    }

    /// Full menu-bar display decision — composes `shouldRender`, `build`, and the
    /// per-account countdown selection into a single deterministic function so the
    /// wiring at the call site can't drift again (v2.2.0 shipped a regression where
    /// the call site passed the wrong count to `shouldRender`; that bug becomes
    /// unrepresentable when the whole decision is one pure function).
    ///
    /// - Parameters:
    ///   - toggleOn: `aibattery_showAllAccountsInMenuBar` UserDefaults value.
    ///   - perAccount: `UsageViewModel.perAccountRateLimits` (keyed by accountId).
    ///   - order: account IDs in display order (typically authenticated, non-pending
    ///     accounts from `AccountStore.accounts`).
    ///   - activeRateLimits: the active account's `RateLimitUsage` from
    ///     `UsageViewModel.snapshot?.rateLimits`. Used for single-account fallback
    ///     and as a countdown floor.
    ///   - activePercent: the active account's percent for the resolved metric mode.
    ///   - metricMode: the resolved metric mode (auto-mode hysteresis output).
    ///   - now: injected current time (for testability).
    ///   - countdownResetDate: per-account countdown resolver. Inject
    ///     `StatusBarManager.countdownResetDate(for:now:)` here.
    ///
    /// - Returns: the four values the menu-bar renderer needs.
    static func resolveDisplay(
        toggleOn: Bool,
        perAccount: [String: RateLimitUsage],
        order: [String],
        activeRateLimits: RateLimitUsage?,
        activePercent: Double,
        metricMode: MetricMode,
        now: Date,
        countdownResetDate: (RateLimitUsage, Date) -> Date?
    ) -> Display {
        // The broken/"exhausted" star is reserved for a genuine throttle signal
        // (explicit API status or a 429). 100% utilization shows a solid red full
        // star instead (color is driven by `percent`), so we do NOT treat >= 100% here.
        let activeIsExhausted = activeRateLimits?.isThrottled ?? false

        let useMulti = shouldRender(toggleOn: toggleOn, fetchedAccountCount: perAccount.count)

        if useMulti {
            let multi = build(order: order, limits: perAccount, metricMode: metricMode)
            let percent = max(multi.worstPercent, activePercent)
            let isExhausted = multi.anyThrottled || activeIsExhausted
            let multiReset = perAccount.values
                .compactMap { countdownResetDate($0, now) }
                .min()
            let activeReset = activeRateLimits.flatMap { countdownResetDate($0, now) }
            let reset = [multiReset, activeReset].compactMap { $0 }.min()
            let text: String = if let reset {
                RateLimitUsage.countdownText(to: reset)
            } else {
                multi.text
            }
            return Display(
                text: text,
                percent: percent,
                isExhausted: isExhausted,
                countdownReset: reset,
                usedMultiAccount: true
            )
        } else {
            let activeReset = activeRateLimits.flatMap { countdownResetDate($0, now) }
            let text: String = if let activeReset {
                // When genuinely throttled, prefix the binding window code (5H/7D) so the
                // menu bar alone tells you whether you're waiting hours or a day+.
                if let rl = activeRateLimits, rl.isThrottled {
                    "\(rl.bindingWindowShortCode) \(RateLimitUsage.countdownText(to: activeReset))"
                } else {
                    RateLimitUsage.countdownText(to: activeReset)
                }
            } else {
                "\(Int(activePercent))%"
            }
            return Display(
                text: text,
                percent: activePercent,
                isExhausted: activeIsExhausted,
                countdownReset: activeReset,
                usedMultiAccount: false
            )
        }
    }

    /// The deterministic output of `resolveDisplay`. `usedMultiAccount` distinguishes
    /// the multi-account branch from the single-account fallback for test assertions.
    struct Display: Equatable {
        let text: String
        let percent: Double
        let isExhausted: Bool
        let countdownReset: Date?
        let usedMultiAccount: Bool
    }

    // MARK: - Private

    private static func percent(for usage: RateLimitUsage, mode: MetricMode) -> Double {
        switch mode {
        case .fiveHour: usage.fiveHourPercent
        case .sevenDay: usage.sevenDayPercent
        case .contextHealth: usage.fiveHourPercent // belt-and-suspenders fallback
        }
    }

    /// Genuine throttle only — 100% utilization is "at capacity", not exhausted.
    private static func isExhausted(_ usage: RateLimitUsage) -> Bool {
        usage.isThrottled
    }
}
