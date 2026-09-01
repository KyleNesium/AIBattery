import SwiftUI

/// Shows the 5-hour rate limit bar.
struct FiveHourBarSection: View {
    let limits: RateLimitUsage
    let source: RateLimitSource?
    var tokenTotal: Int = 0
    /// Whether the displayed snapshot came from a fresh fetch. When `false` (cached /
    /// unconfirmed data), the throttle / "Limit reached" alarm is suppressed — a stale
    /// percentage is fine, a stale alarm is a false alarm. Mirrors the menu bar's gate.
    /// The displayed percentage is always the real API utilization (`limits`); a
    /// fresh-but-wrong near-full spike is corrected upstream by `refresh()`'s spike filter.
    var confirmed: Bool = true

    var body: some View {
        UsageBar(
            label: "5-Hour",
            percent: limits.fiveHourPercent,
            resetsAt: limits.fiveHourReset,
            source: source,
            isBinding: limits.representativeClaim == RateLimitUsage.fiveHourWindow,
            isThrottled: limits.isWindowThrottled(RateLimitUsage.fiveHourWindow),
            estimatedTimeToLimit: limits.estimatedTimeToLimit(for: RateLimitUsage.fiveHourWindow),
            tokenTotal: tokenTotal,
            confirmed: confirmed
        )
        .padding(.horizontal, Spacing.sectionHorizontal)
        .padding(.vertical, Spacing.section)
    }
}

/// Shows the 7-day rate limit bar.
struct SevenDayBarSection: View {
    let limits: RateLimitUsage
    let source: RateLimitSource?
    var tokenTotal: Int = 0
    /// See `FiveHourBarSection.confirmed`.
    var confirmed: Bool = true

    var body: some View {
        UsageBar(
            label: "7-Day",
            percent: limits.sevenDayPercent,
            resetsAt: limits.sevenDayReset,
            source: source,
            isBinding: limits.representativeClaim == RateLimitUsage.sevenDayWindow,
            isThrottled: limits.isWindowThrottled(RateLimitUsage.sevenDayWindow),
            estimatedTimeToLimit: limits.estimatedTimeToLimit(for: RateLimitUsage.sevenDayWindow),
            tokenTotal: tokenTotal,
            confirmed: confirmed
        )
        .padding(.horizontal, Spacing.sectionHorizontal)
        .padding(.vertical, Spacing.section)
    }
}

struct UsageBar: View {
    let label: String
    let percent: Double
    let resetsAt: Date?
    let source: RateLimitSource?
    var isBinding: Bool = false
    var isThrottled: Bool = false
    var estimatedTimeToLimit: TimeInterval?
    var tokenTotal: Int = 0
    /// Whether the displayed data came from a fresh fetch (vs cached/unconfirmed).
    var confirmed: Bool = true

    /// Throttle/limit alarm state, gated on `confirmed`. A stale percentage is fine to
    /// show; a stale "Throttled" / "Limit reached" alarm is a false alarm (the menu bar
    /// already suppresses it via the same gate). The next fresh fetch restores the truth.
    struct AlarmState: Equatable {
        let displayPercent: Double
        let throttled: Bool
        let limitReached: Bool
        let wasExhausted: Bool

        init(percent: Double, isThrottled: Bool, confirmed: Bool) {
            let effectiveThrottled = confirmed && isThrottled
            // Clamp to 100 only on a *confirmed* throttle so the UI doesn't show
            // "99% Throttled"; never fabricate 100% from an unconfirmed throttle.
            let shown = effectiveThrottled ? max(percent, 100) : percent
            displayPercent = shown
            throttled = effectiveThrottled
            // Mutually exclusive with `throttled` — "Throttled" wins over "Limit reached"
            // (matches the footer's if/else-if precedence), so the flag means exactly
            // "show Limit reached". Both are gated on confirmed data.
            limitReached = confirmed && !effectiveThrottled && shown >= 100
            wasExhausted = effectiveThrottled || shown >= 100
        }
    }

    private var alarm: AlarmState {
        AlarmState(percent: percent, isThrottled: isThrottled, confirmed: confirmed)
    }

    /// Display percent — clamps to 100 on a confirmed throttle so the UI doesn't show "99% Throttled".
    private var displayPercent: Double { alarm.displayPercent }

    private var headerTooltip: String {
        var parts = ["\(label) rate limit: \(Int(displayPercent))% used"]
        if isBinding {
            parts.append("This window is the binding constraint")
        }
        if alarm.throttled {
            parts.append("Currently rate limited")
        }
        if let reset = resetsAt {
            let diff = reset.timeIntervalSinceNow
            if diff > 0 {
                parts.append("Resets at \(PopoverFooterView.absoluteTime(reset))")
            }
        }
        if let source {
            parts.append(source.explanation)
        }
        return parts.joined(separator: "\n")
    }

    var body: some View {
        GaugeRow(
            percent: displayPercent,
            barColor: ThemeColors.barColor(percent: displayPercent),
            accessibilityLabel: "\(label) rate limit usage \(Int(displayPercent)) percent",
            accessibilityValue: alarm.throttled ? "Rate limited" : "\(max(0, Int(100 - displayPercent))) percent remaining",
            tickInterval: resetTickInterval,
            headerLeading: {
                HStack(spacing: Spacing.inner) {
                    Text(label)
                        .font(Typography.buttonLabel)
                        .accessibilityAddTraits(.isHeader)
                        .help(headerTooltip)
                    if isBinding {
                        Text("binding")
                            .font(Typography.badgeLabel)
                            .foregroundStyle(ThemeColors.tertiaryLabel)
                            .padding(.horizontal, Spacing.small)
                            .padding(.vertical, Spacing.micro)
                            .background(ThemeColors.badgeFill, in: RoundedRectangle(cornerRadius: Layout.barCornerRadius))
                            .accessibilityLabel("Binding constraint")
                            .help("This window is the active rate limit constraint")
                    }
                    if alarm.throttled {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(Typography.tinyLabel)
                            .foregroundStyle(ThemeColors.danger)
                            .accessibilityLabel("Rate limited")
                            .help("You are currently rate limited")
                    }
                }
            },
            headerTrailing: {
                HStack(spacing: Spacing.inner) {
                    if tokenTotal > 0 {
                        Text(TokenFormatter.format(tokenTotal))
                            .font(Typography.monoCaption)
                            .foregroundStyle(ThemeColors.tertiaryLabel)
                            .frame(width: Layout.tokenColumn, alignment: .trailing)
                            .copyable("\(tokenTotal) tokens")
                    }
                    Text("\(Int(displayPercent))%")
                        .font(Typography.monoValue)
                        .copyable("\(Int(displayPercent))%")
                }
            },
            footer: { now in
                let resetDiff = resetsAt.map { $0.timeIntervalSince(now) }
                let expired = (resetDiff ?? 1) <= 0
                HStack {
                    // Left side: time to limit / status
                    if wasExhausted && expired && displayPercent < 1 {
                        HStack(spacing: Spacing.inner) {
                            Image(systemName: "sparkles")
                                .font(Typography.tinyLabel)
                                .foregroundStyle(ThemeColors.success)
                            Text("Reset")
                                .font(Typography.tinyLabel)
                                .foregroundStyle(ThemeColors.success)
                        }
                    } else if alarm.throttled {
                        Text("Throttled")
                            .font(Typography.tinyLabel)
                            .foregroundStyle(ThemeColors.danger)
                    } else if alarm.limitReached {
                        Text("Limit reached")
                            .font(Typography.tinyLabel)
                            .foregroundStyle(ThemeColors.danger)
                    } else if confirmed, let estimate = estimatedTimeToLimit {
                        // Burn-rate "time to limit" is a prediction off the API utilization —
                        // suppress it on unconfirmed/stale data (same gate as the alarm), else a
                        // stale 100% reading shows "~0s to limit" next to the corrected low %.
                        let estimateText = "~\(DurationFormatter.compact(estimate)) to limit"
                        Text(estimateText)
                            .font(Typography.tinyLabel)
                            .foregroundStyle(ThemeColors.caution)
                            .copyable(estimateText)
                            .help("Estimated time until rate limit based on current burn rate")
                    } else {
                        // No burn rate estimate yet — show remaining percentage
                        let remainingText = "\(max(0, Int(100 - displayPercent)))% remaining"
                        Text(remainingText)
                            .font(Typography.tinyLabel)
                            .foregroundStyle(ThemeColors.secondaryLabel)
                            .copyable(remainingText)
                    }

                    Spacer()

                    // Right side: reset countdown (always shown when available)
                    if let diff = resetDiff {
                        if diff > 0 {
                            let resetText = "Resets in \(DurationFormatter.compact(diff))"
                            Text(resetText)
                                .font(Typography.tinyLabel)
                                .foregroundStyle(ThemeColors.tertiaryLabel)
                                .copyable(resetText)
                        } else if wasExhausted {
                            // Reset time is in the past — window is rolling over
                            Text("Resetting…")
                                .font(Typography.tinyLabel)
                                .foregroundStyle(ThemeColors.caution)
                                .help("Rate limit window is rolling over — values update shortly")
                        }
                    }
                }
            }
        )
    }

    /// Tick every 1s when reset is <60s away (live countdown), otherwise every 10s.
    private var resetTickInterval: TimeInterval {
        guard let reset = resetsAt else { return 10 }
        let diff = reset.timeIntervalSinceNow
        return (diff > 0 && diff < 60) ? 1 : 10
    }

    /// Whether the window was at or near exhaustion (throttled or 100%+).
    /// Reset celebration/soon states only make sense after high usage.
    private var wasExhausted: Bool {
        alarm.wasExhausted
    }
}
