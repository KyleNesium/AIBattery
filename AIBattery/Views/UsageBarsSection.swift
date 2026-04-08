import SwiftUI

/// Shows the 5-hour rate limit bar.
struct FiveHourBarSection: View {
    let limits: RateLimitUsage
    let source: RateLimitSource?
    var tokenTotal: Int = 0

    var body: some View {
        UsageBar(
            label: "5-Hour",
            percent: limits.fiveHourPercent,
            resetsAt: limits.fiveHourReset,
            source: source,
            isBinding: limits.representativeClaim == RateLimitUsage.fiveHourWindow,
            isThrottled: limits.isWindowThrottled(RateLimitUsage.fiveHourWindow),
            estimatedTimeToLimit: limits.estimatedTimeToLimit(for: RateLimitUsage.fiveHourWindow),
            tokenTotal: tokenTotal
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

    var body: some View {
        UsageBar(
            label: "7-Day",
            percent: limits.sevenDayPercent,
            resetsAt: limits.sevenDayReset,
            source: source,
            isBinding: limits.representativeClaim == RateLimitUsage.sevenDayWindow,
            isThrottled: limits.isWindowThrottled(RateLimitUsage.sevenDayWindow),
            estimatedTimeToLimit: limits.estimatedTimeToLimit(for: RateLimitUsage.sevenDayWindow),
            tokenTotal: tokenTotal
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

    /// Display percent — clamps to 100 when throttled so the UI doesn't show "99% Throttled".
    private var displayPercent: Double { isThrottled ? max(percent, 100) : percent }

    private var headerTooltip: String {
        var parts: [String] = ["\(label) rate limit: \(Int(displayPercent))% used"]
        if isBinding { parts.append("This window is the binding constraint") }
        if isThrottled { parts.append("Currently rate limited") }
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
        VStack(alignment: .leading, spacing: Spacing.inner) {
            HStack {
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
                    if isThrottled {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(Typography.tinyLabel)
                            .foregroundStyle(ThemeColors.danger)
                            .accessibilityLabel("Rate limited")
                            .help("You are currently rate limited")
                    }
                }
                Spacer()
                if tokenTotal > 0 {
                    Text(TokenFormatter.format(tokenTotal))
                        .font(Typography.monoCaption)
                        .foregroundStyle(ThemeColors.secondaryLabel)
                        .copyable("\(tokenTotal) tokens")
                }
                Text("\(Int(displayPercent))%")
                    .font(Typography.monoValue)
                    .copyable("\(Int(displayPercent))%")
            }

            GaugeBar(percent: displayPercent, barColor: ThemeColors.barColor(percent: displayPercent))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(label) rate limit usage \(Int(displayPercent)) percent")
            .accessibilityValue(isThrottled ? "Rate limited" : "\(max(0, Int(100 - displayPercent))) percent remaining")

            // TimelineView ticks every second when reset is <60s away for live countdown.
            TimelineView(.periodic(from: .now, by: resetTickInterval)) { context in
            let now = context.date
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
                } else if isThrottled {
                    Text("Throttled")
                        .font(Typography.tinyLabel)
                        .foregroundStyle(ThemeColors.danger)
                } else if displayPercent >= 100 {
                    Text("Limit reached")
                        .font(Typography.tinyLabel)
                        .foregroundStyle(ThemeColors.danger)
                } else if let estimate = estimatedTimeToLimit {
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
            } // TimelineView
        }
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
        isThrottled || displayPercent >= 100
    }
}
