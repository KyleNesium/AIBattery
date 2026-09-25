import SwiftUI

/// The Codex-native replacement for the 5-hour / Weekly bars when the account's plan
/// reports a credit budget (Business / Enterprise spend controls) instead of windows.
/// One gauge: used / limit credits, percent, remaining, and the period reset countdown.
struct CreditBudgetSection: View {
    let limits: RateLimitUsage
    let budget: CodexCreditBudget
    let source: RateLimitSource?
    /// See `FiveHourBarSection.confirmed` — gates the alarm, never the number.
    var confirmed: Bool = true

    private var alarm: UsageBar.AlarmState {
        UsageBar.AlarmState(percent: budget.usedPercent, isThrottled: limits.isThrottled, confirmed: confirmed)
    }

    private var headerTooltip: String {
        var parts = ["Codex credits: \(Int(alarm.displayPercent))% of this period's budget used"]
        parts.append("\(CodexCreditBudget.formatCredits(budget.used)) of \(CodexCreditBudget.formatCredits(budget.limit)) \(budget.unit)s")
        if let planType = budget.planType {
            parts.append("Plan: \(planType)")
        }
        if let reset = budget.resetsAt, reset.timeIntervalSinceNow > 0 {
            parts.append("Resets at \(PopoverFooterView.absoluteTime(reset))")
        }
        if let source {
            parts.append(source.explanation)
        }
        return parts.joined(separator: "\n")
    }

    var body: some View {
        GaugeRow(
            percent: alarm.displayPercent,
            barColor: ThemeColors.barColor(percent: alarm.displayPercent),
            accessibilityLabel: "Codex credits \(Int(alarm.displayPercent)) percent used",
            accessibilityValue: alarm.throttled ? "Credits exhausted" : "\(CodexCreditBudget.formatCredits(budget.remaining)) credits remaining",
            headerLeading: {
                HStack(spacing: Spacing.inner) {
                    Text("Credits")
                        .font(Typography.buttonLabel)
                        .accessibilityAddTraits(.isHeader)
                        .help(headerTooltip)
                    if budget.unlimited {
                        Text("unlimited")
                            .font(Typography.badgeLabel)
                            .foregroundStyle(ThemeColors.tertiaryLabel)
                            .padding(.horizontal, Spacing.small)
                            .padding(.vertical, Spacing.micro)
                            .background(ThemeColors.badgeFill, in: RoundedRectangle(cornerRadius: Layout.barCornerRadius))
                    }
                    if alarm.throttled {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(Typography.tinyLabel)
                            .foregroundStyle(ThemeColors.danger)
                            .accessibilityLabel("Credits exhausted")
                            .help("Your Codex credit budget is exhausted")
                    }
                }
            },
            headerTrailing: {
                HStack(spacing: Spacing.inner) {
                    Text("\(Int(alarm.displayPercent))%")
                        .font(Typography.monoValue)
                        .copyable("\(Int(alarm.displayPercent))%")
                    Text("\(CodexCreditBudget.formatCredits(budget.used)) / \(CodexCreditBudget.formatCredits(budget.limit))")
                        .font(Typography.monoValue)
                        .foregroundStyle(ThemeColors.secondaryLabel)
                        .copyable("\(Int(budget.used)) / \(Int(budget.limit)) \(budget.unit)s")
                }
            },
            footer: { now in
                let resetDiff = budget.resetsAt.map { $0.timeIntervalSince(now) }
                HStack {
                    if alarm.throttled {
                        Text(budget.hasCredits ? "Budget reached" : "Credits depleted")
                            .font(Typography.tinyLabel)
                            .foregroundStyle(ThemeColors.danger)
                    } else if alarm.limitReached {
                        Text("Budget reached")
                            .font(Typography.tinyLabel)
                            .foregroundStyle(ThemeColors.danger)
                    } else {
                        let remainingText = "\(CodexCreditBudget.formatCredits(budget.remaining)) remaining"
                        Text(remainingText)
                            .font(Typography.tinyLabel)
                            .foregroundStyle(ThemeColors.secondaryLabel)
                            .copyable(remainingText)
                    }
                    Spacer()
                    if let diff = resetDiff, diff > 0 {
                        let resetText = "Resets in \(DurationFormatter.compact(diff))"
                        Text(resetText)
                            .font(Typography.tinyLabel)
                            .foregroundStyle(ThemeColors.tertiaryLabel)
                            .copyable(resetText)
                    }
                }
            }
        )
        .padding(.horizontal, Spacing.sectionHorizontal)
        .padding(.vertical, Spacing.section)
    }
}
