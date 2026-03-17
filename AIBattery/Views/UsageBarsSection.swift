import SwiftUI

/// Shows the 5-hour rate limit bar.
struct FiveHourBarSection: View {
    let limits: RateLimitUsage

    var body: some View {
        UsageBar(
            label: "5-Hour",
            percent: limits.fiveHourPercent,
            resetsAt: limits.fiveHourReset,
            isBinding: limits.representativeClaim == RateLimitUsage.fiveHourWindow,
            isThrottled: limits.fiveHourStatus == "throttled"
                || (limits.isThrottled && limits.fiveHourPercent >= 100),
            estimatedTimeToLimit: limits.estimatedTimeToLimit(for: RateLimitUsage.fiveHourWindow)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

/// Shows the 7-day rate limit bar.
struct SevenDayBarSection: View {
    let limits: RateLimitUsage

    var body: some View {
        UsageBar(
            label: "7-Day",
            percent: limits.sevenDayPercent,
            resetsAt: limits.sevenDayReset,
            isBinding: limits.representativeClaim == RateLimitUsage.sevenDayWindow,
            isThrottled: limits.sevenDayStatus == "throttled"
                || (limits.isThrottled && limits.sevenDayPercent >= 100),
            estimatedTimeToLimit: limits.estimatedTimeToLimit(for: RateLimitUsage.sevenDayWindow)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct UsageBar: View {
    let label: String
    let percent: Double
    let resetsAt: Date?
    var isBinding: Bool = false
    var isThrottled: Bool = false
    var estimatedTimeToLimit: TimeInterval?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                HStack(spacing: 4) {
                    Text(label)
                        .font(.subheadline.bold())
                        .accessibilityAddTraits(.isHeader)
                    if isBinding {
                        Text("binding")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(ThemeColors.tertiaryLabel)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(ThemeColors.badgeFill, in: RoundedRectangle(cornerRadius: 3))
                            .accessibilityLabel("Binding constraint")
                            .help("This window is the active rate limit constraint")
                    }
                    if isThrottled {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(ThemeColors.danger)
                            .accessibilityLabel("Rate limited")
                            .help("You are currently rate limited")
                    }
                }
                Spacer()
                Text("\(Int(percent))%")
                    .font(.system(.headline, design: .monospaced, weight: .semibold))
                    
                    
                    .copyable("\(Int(percent))%")
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(ThemeColors.trackFill)
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(ThemeColors.barColor(percent: percent))
                        .frame(width: geometry.size.width * min(CGFloat(percent) / 100.0, 1.0), height: 8)
                        
                }
            }
            .frame(height: 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(label) rate limit usage \(Int(percent)) percent")
            .accessibilityValue(isThrottled ? "Rate limited" : "\(max(0, Int(100 - percent))) percent remaining")

            // TimelineView ticks every second when reset is <60s away for live countdown.
            TimelineView(.periodic(from: .now, by: resetTickInterval)) { context in
            let now = context.date
            let resetDiff = resetsAt.map { $0.timeIntervalSince(now) }
            let expired = (resetDiff ?? 1) <= 0
            HStack {
                // Left side: time to limit / status
                if wasExhausted && expired && percent < 1 {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(.green)
                        Text("Reset")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                    .transition(.opacity)
                } else if isThrottled {
                    Text("Throttled")
                        .font(.caption2)
                        .foregroundStyle(ThemeColors.danger)
                        .transition(.opacity)
                } else if let estimate = estimatedTimeToLimit {
                    let estimateText = "~\(DurationFormatter.compact(estimate)) to limit"
                    Text(estimateText)
                        .font(.caption2)
                        .foregroundStyle(ThemeColors.caution)
                        .copyable(estimateText)
                } else {
                    // No burn rate estimate yet — show remaining percentage
                    let remainingText = "\(max(0, Int(100 - percent)))% remaining"
                    Text(remainingText)
                        .font(.caption2)
                        .foregroundStyle(ThemeColors.secondaryLabel)
                        .copyable(remainingText)
                }

                Spacer()

                // Right side: reset countdown (always shown when available)
                if let diff = resetDiff {
                    if diff <= 0 && wasExhausted && percent >= 1 {
                        Text("Resets soon")
                            .font(.caption2)
                            .foregroundStyle(ThemeColors.caution)
                            .help("Rate limit window is resetting")
                    } else if diff > 0 {
                        let resetText = "Resets in \(DurationFormatter.compact(diff))"
                        Text(resetText)
                            .font(.caption2)
                            .foregroundStyle(ThemeColors.tertiaryLabel)
                            .copyable(resetText)
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
        isThrottled || percent >= 100
    }
}
