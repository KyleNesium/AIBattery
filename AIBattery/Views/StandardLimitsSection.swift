import SwiftUI

/// Fallback display when unified 5h/7d rate limit windows are unavailable.
/// Shows per-minute request and token limits from standard Anthropic API headers.
struct StandardLimitsSection: View {
    let limits: StandardRateLimits

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.gap) {
            HStack(spacing: Spacing.inner) {
                Image(systemName: "info.circle")
                    .font(Typography.tinyLabel)
                    .foregroundStyle(ThemeColors.tertiaryLabel)
                    .accessibilityHidden(true)
                Text("Showing API rate limits (5h/7d usage unavailable)")
                    .font(Typography.tinyLabel)
                    .foregroundStyle(ThemeColors.secondaryLabel)
            }

            if limits.requestsLimit > 0 {
                StandardLimitBar(
                    label: "Requests",
                    used: limits.requestsLimit - limits.requestsRemaining,
                    limit: limits.requestsLimit,
                    remaining: limits.requestsRemaining,
                    resetsAt: limits.requestsReset,
                    isExhausted: limits.isRequestsExhausted
                )
            }

            if limits.tokensLimit > 0 {
                StandardLimitBar(
                    label: "Tokens",
                    used: limits.tokensLimit - limits.tokensRemaining,
                    limit: limits.tokensLimit,
                    remaining: limits.tokensRemaining,
                    resetsAt: limits.tokensReset,
                    isExhausted: limits.isTokensExhausted
                )
            }
        }
        .padding(.horizontal, Spacing.sectionHorizontal)
        .padding(.vertical, Spacing.section)
    }
}

/// A single standard rate limit bar with remaining/limit display.
private struct StandardLimitBar: View {
    let label: String
    let used: Int
    let limit: Int
    let remaining: Int
    let resetsAt: Date?
    let isExhausted: Bool

    private var percent: Double {
        guard limit > 0 else { return 0 }
        return Double(used) / Double(limit) * 100.0
    }

    var body: some View {
        GaugeRow(
            percent: percent,
            barColor: ThemeColors.barColor(percent: percent),
            accessibilityLabel: "\(label) rate limit usage \(Int(percent)) percent",
            accessibilityValue: isExhausted ? "Limit reached" : "\(TokenFormatter.format(remaining)) remaining",
            headerLeading: {
                HStack(spacing: Spacing.inner) {
                    Text(label)
                        .font(Typography.buttonLabel)
                    if isExhausted {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(Typography.tinyLabel)
                            .foregroundStyle(ThemeColors.danger)
                            .accessibilityHidden(true)
                    }
                }
            },
            headerTrailing: {
                Text("\(TokenFormatter.format(remaining))/\(TokenFormatter.format(limit))")
                    .font(Typography.monoValue)
                    .copyable("\(remaining)/\(limit)")
            },
            footer: { now in
                HStack {
                    if isExhausted {
                        Text("Limit reached")
                            .font(Typography.tinyLabel)
                            .foregroundStyle(ThemeColors.danger)
                    } else {
                        Text("\(TokenFormatter.format(remaining)) remaining")
                            .font(Typography.tinyLabel)
                            .foregroundStyle(ThemeColors.secondaryLabel)
                    }

                    Spacer()

                    if let reset = resetsAt {
                        let diff = reset.timeIntervalSince(now)
                        if diff > 0 {
                            Text("Resets in \(DurationFormatter.compact(diff))")
                                .font(Typography.tinyLabel)
                                .foregroundStyle(ThemeColors.tertiaryLabel)
                        }
                    }
                }
            }
        )
    }
}
