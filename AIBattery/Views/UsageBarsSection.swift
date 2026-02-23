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
            isThrottled: limits.fiveHourStatus == "throttled",
            estimatedTimeToLimit: limits.estimatedTimeToLimit(for: RateLimitUsage.fiveHourWindow)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
            isThrottled: limits.sevenDayStatus == "throttled",
            estimatedTimeToLimit: limits.estimatedTimeToLimit(for: RateLimitUsage.sevenDayWindow)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
                    if isBinding {
                        Text("binding")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 3))
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
                    .font(.system(.title3, design: .monospaced, weight: .semibold))
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.4), value: Int(percent))
                    .copyable("\(Int(percent))%")
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.1))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(ThemeColors.barColor(percent: percent))
                        .frame(width: geometry.size.width * min(CGFloat(percent) / 100.0, 1.0), height: 8)
                        .animation(.easeInOut(duration: 0.4), value: percent)
                }
            }
            .frame(height: 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(label) rate limit usage \(Int(percent)) percent")
            .accessibilityValue(isThrottled ? "Rate limited" : "\(Int(100 - percent)) percent remaining")

            HStack {
                if isThrottled {
                    Text("Rate limited")
                        .font(.caption2)
                        .foregroundStyle(ThemeColors.danger)
                } else if let estimate = estimatedTimeToLimit {
                    Text("~\(formatDuration(estimate)) to limit")
                        .font(.caption2)
                        .foregroundStyle(ThemeColors.caution)
                } else {
                    Text("\(Int(100 - percent))% remaining")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let resetsAt {
                    Text("Resets \(resetTimeString(resetsAt))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(max(minutes, 1))m"
    }

    private func resetTimeString(_ date: Date) -> String {
        let now = Date()
        let diff = date.timeIntervalSince(now)
        guard diff > 0 else { return "soon" }

        let hours = Int(diff) / 3600
        let minutes = (Int(diff) % 3600) / 60

        if hours > 24 {
            let days = hours / 24
            return "in \(days)d \(hours % 24)h"
        } else if hours > 0 {
            return "in \(hours)h \(minutes)m"
        } else {
            return "in \(minutes)m"
        }
    }
}
