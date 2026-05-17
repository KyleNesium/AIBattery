import SwiftUI

/// Shows estimated 5h/7d usage from local JSONL token counts when
/// Anthropic's unified rate limit headers are unavailable.
/// Renders a single window (5h or 7d) based on the active metric mode,
/// so the mode selector and auto-mode work the same as with API data.
struct LocalEstimateSection: View {
    let fiveHourTokens: Int
    let sevenDayTokens: Int
    let window: MetricMode

    private var activeTokens: Int {
        window == .fiveHour ? fiveHourTokens : sevenDayTokens
    }

    private var activePercent: Double? {
        window == .fiveHour
            ? LocalUsageEstimate.fiveHourPercent(tokens: fiveHourTokens)
            : LocalUsageEstimate.sevenDayPercent(tokens: sevenDayTokens)
    }

    private var activeLimit: Int? {
        window == .fiveHour
            ? LocalUsageEstimate.effectiveFiveHourLimit
            : LocalUsageEstimate.effectiveSevenDayLimit
    }

    private var limitSource: LocalUsageEstimate.LimitSource? {
        LocalUsageEstimate.limitSource(for: window)
    }

    private var activeLabel: String {
        window == .fiveHour ? "5-Hour" : "7-Day"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.gap) {
            localUsageBar(
                label: activeLabel,
                tokens: activeTokens,
                percent: activePercent,
                limit: activeLimit
            )
        }
        .padding(.horizontal, Spacing.sectionHorizontal)
        .padding(.vertical, Spacing.section)
    }

    private func localUsageBar(label: String, tokens: Int, percent: Double?, limit: Int?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.inner) {
            HStack {
                Text("\(label) Usage")
                    .font(Typography.buttonLabel)
                Spacer()
                if let pct = percent {
                    Text("\(Int(pct))%")
                        .font(Typography.monoValue)
                        .copyable("\(Int(pct))%")
                        .accessibilityLabel("\(label) usage \(Int(pct)) percent")
                }
                tokenLabel(tokens: tokens, limit: limit)
            }

            if let pct = percent {
                GaugeBar(percent: pct, barColor: ThemeColors.barColor(percent: pct))
            }

            // Remaining tokens
            if let limit, limit > tokens {
                let remaining = limit - tokens
                let prefix = limitSource == .planEstimate ? "~" : ""
                HStack {
                    Spacer()
                    Text("\(prefix)\(TokenFormatter.format(remaining)) remaining")
                        .font(Typography.tinyLabel)
                        .foregroundStyle(ThemeColors.secondaryLabel)
                }
            }
        }
    }

    @ViewBuilder
    private func tokenLabel(tokens: Int, limit: Int?) -> some View {
        if let limit {
            let prefix = limitSource == .planEstimate ? "~" : ""
            Text("\(TokenFormatter.format(tokens)) / \(prefix)\(TokenFormatter.format(limit))")
                .font(Typography.monoValue)
                .foregroundStyle(ThemeColors.secondaryLabel)
                .copyable("\(tokens) / \(limit)")
        } else {
            Text(TokenFormatter.format(tokens) + " tokens")
                .font(Typography.monoValue)
                .foregroundStyle(.primary)
                .copyable("\(tokens)")
        }
    }
}
