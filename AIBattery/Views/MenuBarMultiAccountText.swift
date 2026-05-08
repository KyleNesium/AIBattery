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

    /// Earliest **future** reset Date across all known accounts, for the resolved mode.
    /// Past resets are filtered (a window that already reset shouldn't pin the
    /// countdown to a stale date when another window is still exhausted).
    static func worstResetDate(
        limits: [String: RateLimitUsage],
        metricMode: MetricMode,
        now: Date
    ) -> Date? {
        let resolvedMode: MetricMode = (metricMode == .contextHealth) ? .fiveHour : metricMode
        let candidates: [Date] = limits.values.compactMap { usage -> Date? in
            let reset: Date?
            switch resolvedMode {
            case .fiveHour: reset = usage.fiveHourReset
            case .sevenDay: reset = usage.sevenDayReset
            case .contextHealth: reset = usage.fiveHourReset // unreached after fallback above
            }
            guard let r = reset, r > now else { return nil }
            return r
        }
        return candidates.min()
    }

    /// Whether the toggle would render a multi-account display given current state.
    /// Encapsulates the gate so callers don't repeat the conditions.
    static func shouldRender(
        toggleOn: Bool,
        accountCount: Int
    ) -> Bool {
        toggleOn && accountCount >= 2
    }

    // MARK: - Private

    private static func percent(for usage: RateLimitUsage, mode: MetricMode) -> Double {
        switch mode {
        case .fiveHour: return usage.fiveHourPercent
        case .sevenDay: return usage.sevenDayPercent
        case .contextHealth: return usage.fiveHourPercent // belt-and-suspenders fallback
        }
    }

    private static func isExhausted(_ usage: RateLimitUsage) -> Bool {
        usage.isThrottled
            || usage.fiveHourPercent >= 100
            || usage.sevenDayPercent >= 100
    }
}
