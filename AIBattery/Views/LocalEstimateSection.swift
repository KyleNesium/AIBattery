import SwiftUI

/// Shows estimated 5h/7d usage from local JSONL token counts when
/// Anthropic's unified rate limit headers are unavailable.
/// Renders a single window (5h or 7d) based on the active metric mode,
/// so the mode selector and auto-mode work the same as with API data.
struct LocalEstimateSection: View {
    let fiveHourTokens: Int
    let sevenDayTokens: Int
    let window: MetricMode

    private var isCalibrated: Bool { LocalUsageEstimate.isCalibrated }

    private var activeTokens: Int {
        window == .fiveHour ? fiveHourTokens : sevenDayTokens
    }

    private var activePercent: Double? {
        window == .fiveHour
            ? LocalUsageEstimate.fiveHourPercent(tokens: fiveHourTokens)
            : LocalUsageEstimate.sevenDayPercent(tokens: sevenDayTokens)
    }

    private var activeLabel: String {
        window == .fiveHour ? "5-Hour" : "7-Day"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.gap) {
            localUsageBar(
                label: activeLabel,
                tokens: activeTokens,
                percent: activePercent
            )
        }
        .padding(.horizontal, Spacing.sectionHorizontal)
        .padding(.vertical, Spacing.section)
    }

    @ViewBuilder
    private func localUsageBar(label: String, tokens: Int, percent: Double?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.inner) {
            HStack {
                Text("\(label) Usage")
                    .font(Typography.buttonLabel)
                Spacer()
                if let pct = percent {
                    Text("\(Int(pct))%")
                        .font(Typography.monoValue)
                        .copyable("\(Int(pct))%")
                }
                Text(TokenFormatter.format(tokens) + " tokens")
                    .font(Typography.monoValue)
                    .foregroundStyle(percent != nil ? ThemeColors.secondaryLabel : .primary)
                    .copyable("\(tokens)")
            }

            if let pct = percent {
                GaugeBar(percent: pct, barColor: ThemeColors.barColor(percent: pct))
            }
        }
    }
}
