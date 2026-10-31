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
    ///   - providers: per-account provider, keyed by account ID. Defaults to empty (single provider mode).
    ///   - limits: per-account `RateLimitUsage`, keyed by account ID. Missing entries → "—".
    ///     because context health is per-session, not per-account, and would not
    ///     produce a meaningful per-account number.
    static func build(
        order: [String],
        providers: [String: AIProvider] = [:],
        limits: [String: RateLimitUsage],
        apiLimits: [String: StandardRateLimits] = [:]
    ) -> Output {
        let parts: [String] = order.map { id in
            guard let pct = headlinePercent(id: id, limits: limits, apiLimits: apiLimits) else { return "—" }
            return PercentFormat.display(pct)
        }

        // Determine if we have mixed providers (single provider vs mixed).
        // Derived from the accounts actually being DISPLAYED (`order`), not every known
        // entry in `providers` — a provider whose accounts were all filtered out of
        // `order` (e.g. a fetch failure) must not force glyph grouping on regardless.
        let distinctProviders = Set(order.compactMap { providers[$0] })
        let hasMixedProviders = distinctProviders.count > 1

        let text: String = if hasMixedProviders {
            // Group by provider and emit glyph-prefixed groups joined by two spaces
            buildMixedProviderText(order: order, providers: providers, parts: parts)
        } else {
            // Single provider or empty providers: legacy format (no glyphs)
            parts.joined(separator: separator)
        }

        // Scan only what is on screen. `limits` can hold entries `order` filters out
        // (pending, API-key and signed-out accounts are dropped in `multiAccountDisplayIDs`),
        // and driving the icon off those turned the star red — or started a countdown — for
        // an account with no visible percentage beside it.
        let shown = order.compactMap { limits[$0] }
        let shownAPI = order.compactMap { apiLimits[$0] }
        let worstPercent = order
            .compactMap { headlinePercent(id: $0, limits: limits, apiLimits: apiLimits) }
            .max() ?? 0
        let anyThrottled = shown.contains { isExhausted($0) }
            || shownAPI.contains { $0.isRequestsExhausted || $0.isTokensExhausted }
        return Output(text: text, worstPercent: worstPercent, anyThrottled: anyThrottled)
    }

    /// Build text for mixed-provider display: groups prefixed with glyphs, joined by two spaces.
    /// e.g. "✦\u{00A0}42%\u{00A0}|\u{00A0}23%  ⬡\u{00A0}57%"
    private static func buildMixedProviderText(
        order: [String],
        providers: [String: AIProvider],
        parts: [String]
    ) -> String {
        // Group accounts by provider in order
        var groups: [(provider: AIProvider, accountParts: [String])] = []
        var currentProvider: AIProvider?
        var currentParts: [String] = []

        for (i, id) in order.enumerated() {
            // An id with no provider entry is skipped rather than drawn under Claude's
            // mark. The map is built from every account, so this is defensive only —
            // but mislabelling someone's Codex usage as Claude is worse than omitting it.
            guard let provider = providers[id] else { continue }
            if currentProvider == nil {
                currentProvider = provider
            }

            if provider == currentProvider {
                currentParts.append(parts[i])
            } else {
                // Provider changed: save current group and start new one
                if let provider = currentProvider {
                    groups.append((provider: provider, accountParts: currentParts))
                }
                currentProvider = provider
                currentParts = [parts[i]]
            }
        }

        // Add the final group
        if let provider = currentProvider {
            groups.append((provider: provider, accountParts: currentParts))
        }

        // Format each group with glyph + separator, then join groups by two spaces
        let formattedGroups = groups.map { group in
            let groupText = group.accountParts.joined(separator: separator)
            return "\(group.provider.glyph)\u{00A0}\(groupText)"
        }

        return formattedGroups.joined(separator: "  ")
    }

    /// Countdown text, prefixed with the window code when one is known.
    private static func countdownText(reset: Date, windowCode: String?) -> String {
        guard let windowCode else { return RateLimitUsage.countdownText(to: reset) }
        return "\(windowCode) \(RateLimitUsage.countdownText(to: reset))"
    }

    /// The binding window short code of the displayed, throttled account whose reset is
    /// the one being counted down.
    private static func bindingWindowCode(
        for reset: Date,
        order: [String],
        limits: [String: RateLimitUsage],
        now: Date,
        countdownResetDate: (RateLimitUsage, Date) -> Date?
    ) -> String? {
        for id in order {
            guard let usage = limits[id], usage.isThrottled,
                  countdownResetDate(usage, now) == reset else { continue }
            return usage.bindingWindowShortCode
        }
        return nil
    }

    /// Whether the toggle would render a multi-account display given current state.
    ///
    /// - Parameter fetchedAccountCount: count of accounts with **fetched rate-limit
    ///   data** (windowed + API-key readings, i.e. `perAccountReadings.count`), NOT the count of
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
    ///   - apiLimits: `UsageViewModel.perAccountAPILimits` — Codex API-key accounts' per-minute
    ///     limits; their slot shows `peakPercent` regardless of `metricMode`.
    ///   - providers: per-account provider, keyed by account ID. Defaults to empty (single provider mode).
    ///   - order: account IDs in display order (typically authenticated, non-pending
    ///     accounts from `AccountStore.accounts`).
    ///   - activeRateLimits: the active account's `RateLimitUsage` from
    ///     `UsageViewModel.snapshot?.rateLimits`. Used for single-account fallback
    ///     and as a countdown floor.
    ///   - activePercent: the active account's percent for the resolved metric mode.
    ///   - metricMode: the resolved metric mode (auto-mode hysteresis output).
    ///   - confirmed: whether the displayed data came from a fresh fetch. When `false`
    ///     (data served from cache, e.g. the instant-paint right after wake before the
    ///     first fetch lands), the throttle alarm is suppressed — no broken star, no
    ///     "limit reached" countdown — and the last-known percentage shows instead. A
    ///     stale number is fine; a stale "you're blocked" alarm is a false alarm. The
    ///     next confirmed fetch restores the real throttle state. Defaults to `true`.
    ///   - now: injected current time (for testability).
    ///   - countdownResetDate: per-account countdown resolver. Inject
    ///     `StatusBarManager.countdownResetDate(for:now:)` here.
    ///
    /// - Returns: the four values the menu-bar renderer needs.
    static func resolveDisplay(
        toggleOn: Bool,
        perAccount: [String: RateLimitUsage],
        apiLimits: [String: StandardRateLimits] = [:],
        providers: [String: AIProvider] = [:],
        order: [String],
        activeRateLimits: RateLimitUsage?,
        activePercent: Double,
        metricMode: MetricMode,
        confirmed: Bool = true,
        now: Date,
        countdownResetDate: (RateLimitUsage, Date) -> Date?
    ) -> Display {
        // The broken/"exhausted" star is reserved for a genuine throttle signal
        // (explicit API status or a 429). 100% utilization shows a solid red full
        // star instead (color is driven by `percent`), so we do NOT treat >= 100% here.
        // `confirmed` gates the alarm: on cached/unconfirmed data we never show the
        // broken star or a countdown — only the last-known percentage.
        let activeIsExhausted = confirmed && (activeRateLimits?.isThrottled ?? false)

        // Count only accounts that are BOTH displayed and have data. `perAccount` can
        // hold entries `order` filters out, and gating on its raw count meant an empty
        // `order` with two stale entries took the multi branch and rendered an empty
        // string — the same class of bug as the v2.2.0 "— | —" regression, inverted.
        let fetchedCount = order.filter { perAccount[$0] != nil || apiLimits[$0] != nil }.count
        let useMulti = shouldRender(toggleOn: toggleOn, fetchedAccountCount: fetchedCount)
        // With several accounts but the list turned off, the bar still has to agree with
        // the overview the popover opens on: one number, the worst account's headline.
        // Only a genuinely single-account bar follows the metric tabs.
        let useWorstOnly = !useMulti && fetchedCount >= 2 && order.count >= 2

        if useMulti {
            let multi = build(order: order, providers: providers, limits: perAccount, apiLimits: apiLimits)
            let percent = max(multi.worstPercent, activePercent)
            let isExhausted = confirmed && (multi.anyThrottled || (activeRateLimits?.isThrottled ?? false))
            let reset: Date? = confirmed
                ? [
                    // Only displayed accounts — same reason as `build`'s worst/throttled
                    // scan: a filtered-out entry must not start a countdown the user
                    // cannot trace to any visible percentage.
                    order.compactMap { perAccount[$0] }.compactMap { countdownResetDate($0, now) }.min(),
                    activeRateLimits.flatMap { countdownResetDate($0, now) },
                ].compactMap { $0 }.min()
                : nil
            let text: String = if let reset {
                // Prefix the binding window code (5H/7D) of whichever displayed account
                // owns the soonest reset, exactly as the single-account branch does.
                // Without it a colour-blind user with two accounts had no non-colour cue
                // that the bar had switched from percentages to a countdown.
                countdownText(reset: reset, windowCode: bindingWindowCode(for: reset, order: order, limits: perAccount, now: now, countdownResetDate: countdownResetDate))
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
        } else if useWorstOnly {
            let worst = order
                .compactMap { headlinePercent(id: $0, limits: perAccount, apiLimits: apiLimits) }
                .max() ?? activePercent
            let shown = order.compactMap { perAccount[$0] }
            let shownAPI = order.compactMap { apiLimits[$0] }
            let isExhausted = confirmed && (
                shown.contains { $0.isThrottled }
                    || shownAPI.contains { $0.isRequestsExhausted || $0.isTokensExhausted }
            )
            let reset: Date? = confirmed
                ? shown.compactMap { countdownResetDate($0, now) }.min()
                : nil
            let text: String = if let reset {
                RateLimitUsage.countdownText(to: reset)
            } else {
                PercentFormat.display(worst)
            }
            return Display(
                text: text,
                percent: worst,
                isExhausted: isExhausted,
                countdownReset: reset,
                usedMultiAccount: false
            )
        } else {
            let activeReset: Date? = confirmed ? activeRateLimits.flatMap { countdownResetDate($0, now) } : nil
            let text: String = if let activeReset {
                // When genuinely throttled, prefix the binding window code (5H/7D) so the
                // menu bar alone tells you whether you're waiting hours or a day+.
                if let rl = activeRateLimits, rl.isThrottled {
                    "\(rl.bindingWindowShortCode) \(RateLimitUsage.countdownText(to: activeReset))"
                } else {
                    RateLimitUsage.countdownText(to: activeReset)
                }
            } else {
                PercentFormat.display(activePercent)
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

    /// What VoiceOver reads for the status item.
    ///
    /// The image carries the number; the accessibility value has to carry the meaning.
    /// It used to be the raw rendered string, so VoiceOver said "AI Battery, 63%" with
    /// no hint of *what* 63% was, read the separator as "42% vertical bar 23%", spoke
    /// `—` literally, and never mentioned being throttled on a multi-account bar.
    ///
    /// - Parameters:
    ///   - display: the resolved menu-bar display.
    ///   - metricLabel: the active metric in the provider's own words, from
    ///     `MetricMode.shortLabel(provider:kind:)` — passed in rather than derived here
    ///     so there is one source for that vocabulary.
    ///   - providerNames: glyph → spoken provider name, applied to mixed-provider text.
    static func spokenDescription(
        display: Display,
        metricLabel: String,
        providerNames: (String) -> String = { $0 }
    ) -> String {
        var body = providerNames(display.text)
            .replacingOccurrences(of: separator, with: ", ")
            .replacingOccurrences(of: "\u{2014}", with: "no data")
            .replacingOccurrences(of: "  ", with: ", ")
        if body.isEmpty {
            body = "no data"
        }

        var parts = ["AI Battery"]
        if display.countdownReset != nil {
            // A countdown replaces the percentage entirely, so "N%" vocabulary would lie.
            parts.append("limit reached")
            parts.append("resets in \(body)")
        } else if display.usedMultiAccount {
            parts.append("usage by account")
            parts.append(body)
            if display.isExhausted {
                parts.append("limit reached")
            }
        } else {
            parts.append(metricLabel)
            parts.append(body)
            if display.isExhausted {
                parts.append("limit reached")
            }
        }
        return parts.joined(separator: ", ")
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

    /// What one account contributes to the menu bar when several are on screen: the
    /// SAME number its overview card leads with — the fuller window, the credit budget,
    /// or the busier per-minute limit.
    ///
    /// The metric tabs (5H / 7D / Context) choose what the *detail* view is about, so a
    /// single-account menu bar follows them. With several accounts there is no single
    /// metric being looked at, and following the tab meant the bar could read "6%" for an
    /// account whose card said 94% — the 5-hour window was quiet while the weekly one was
    /// nearly spent. The headline is the number that actually tells you to stop.
    static func headlinePercent(
        id: String,
        limits: [String: RateLimitUsage],
        apiLimits: [String: StandardRateLimits]
    ) -> Double? {
        // Delegate to the one definition of "headline" so the bar and the cards cannot
        // drift. `fetchedAt`/`isCached` play no part in the number.
        guard limits[id] != nil || apiLimits[id] != nil else { return nil }
        return AccountReading(
            windows: limits[id], apiLimits: apiLimits[id],
            fetchedAt: .distantPast, isCached: false, source: nil
        ).worstPercent
    }

    /// Genuine throttle only — 100% utilization is "at capacity", not exhausted.
    private static func isExhausted(_ usage: RateLimitUsage) -> Bool {
        usage.isThrottled
    }
}
