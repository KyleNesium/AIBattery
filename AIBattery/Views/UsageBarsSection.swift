import SwiftUI

/// Shows the 5-hour rate limit bar.
struct FiveHourBarSection: View {
    let limits: RateLimitUsage

    var body: some View {
        UsageBar(
            label: "5-Hour",
            percent: limits.fiveHourPercent,
            resetsAt: limits.fiveHourReset,
            isBinding: limits.representativeClaim == "five_hour",
            isThrottled: limits.fiveHourStatus == "throttled"
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
            isBinding: limits.representativeClaim == "seven_day",
            isThrottled: limits.sevenDayStatus == "throttled"
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                HStack(spacing: 4) {
                    Text(label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if isBinding {
                        Text("binding")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 3))
                            .accessibilityLabel("Binding constraint")
                    }
                    if isThrottled {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .accessibilityLabel("Rate limited")
                    }
                }
                Spacer()
                Text("\(Int(percent))%")
                    .font(.system(.title3, design: .monospaced, weight: .semibold))
                    .copyable("\(Int(percent))%")
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.1))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(colorForPercent(percent))
                        .frame(width: geometry.size.width * min(CGFloat(percent) / 100.0, 1.0), height: 8)
                }
            }
            .frame(height: 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(label) rate limit usage \(Int(percent)) percent")
            .accessibilityValue(isThrottled ? "Rate limited" : "\(Int(100 - percent)) percent remaining")

            HStack {
                Text(isThrottled ? "Rate limited" : "\(Int(100 - percent))% remaining")
                    .font(.caption2)
                    .foregroundStyle(isThrottled ? Color.red : Color.secondary.opacity(0.6))
                if let resetsAt {
                    Spacer()
                    Text("Resets \(resetTimeString(resetsAt))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func colorForPercent(_ pct: Double) -> Color {
        switch pct {
        case 0..<50: return .green
        case 50..<80: return .yellow
        case 80..<95: return .orange
        default: return .red
        }
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
