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

    /// Tooltip's "Plan: …" line — the reported limit name (e.g. a workspace's named spend
    /// cap) when present, else the bare plan type, else nothing.
    nonisolated static func planLine(limitName: String?, planType: String?) -> String? {
        let name = limitName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty {
            return "Plan: \(name)"
        }
        if let planType, !planType.isEmpty {
            return "Plan: \(planType)"
        }
        return nil
    }

    private var headerTooltip: String {
        var parts: [String] = if budget.isUncapped {
            ["Codex credits: this plan has no individual spend cap, so there is nothing to meter"]
        } else {
            [
                "Codex credits: \(PercentFormat.display(alarm.displayPercent)) of this period's budget used",
                "\(CodexCreditBudget.formatCredits(budget.used)) of \(CodexCreditBudget.formatCredits(budget.limit)) \(budget.unit)s",
            ]
        }
        if let line = Self.planLine(limitName: budget.limitName, planType: budget.planType) {
            parts.append(line)
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
            accessibilityLabel: "Codex credits \(PercentFormat.spoken(alarm.displayPercent)) used",
            accessibilityValue: alarm.throttled ? "Credit budget reached" : (budget.isUncapped ? "No spend cap" : "\(CodexCreditBudget.formatCredits(budget.remaining)) credits remaining"),
            // The plan name, reset time and provenance live only in the tooltip, which
            // VoiceOver never sees.
            accessibilityHint: headerTooltip.replacingOccurrences(of: "\n", with: ", "),
            headerLeading: {
                HStack(spacing: Spacing.inner) {
                    Text("Credits")
                        .font(Typography.buttonLabel)
                        .accessibilityAddTraits(.isHeader)
                        .help(headerTooltip)
                    // Only the SPEND CAP belongs on this bar. `budget.unlimited` is
                    // `credits.unlimited` — the purchased-credit BALANCE being unlimited —
                    // which is an independent quantity shown by `CreditBalanceRow`. Pairing
                    // it with this bar labelled an 85%-consumed finite budget "unlimited".
                    if budget.isUncapped, !alarm.throttled {
                        Text("no cap")
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
                            .accessibilityLabel("Credit budget reached")
                            .help("Your Codex credit budget has been reached")
                    }
                }
            },
            headerTrailing: {
                HStack(spacing: Spacing.inner) {
                    if budget.isUncapped {
                        Text("—")
                            .font(Typography.monoValue)
                            .foregroundStyle(ThemeColors.secondaryLabel)
                            .help("No individual spend cap on this plan")
                    } else {
                        Text(PercentFormat.display(alarm.displayPercent))
                            .font(Typography.monoValue)
                            .copyable(PercentFormat.display(alarm.displayPercent))
                        Text("\(CodexCreditBudget.formatCredits(budget.used)) / \(CodexCreditBudget.formatCredits(budget.limit))")
                            .font(Typography.monoValue)
                            .foregroundStyle(ThemeColors.secondaryLabel)
                            .copyable("\(Int(budget.used)) / \(Int(budget.limit)) \(budget.unit)s")
                    }
                }
            },
            footer: { now in
                let resetDiff = budget.resetsAt.map { $0.timeIntervalSince(now) }
                HStack {
                    if alarm.throttled {
                        // One verb for one state: a limit is "reached". "Depleted"/"exhausted" said the
                        // same thing in two other words elsewhere in the same popover.
                        Text(budget.hasCredits ? "Budget reached" : "No credits left")
                            .font(Typography.tinyLabel)
                            .foregroundStyle(ThemeColors.danger)
                    } else if budget.isUncapped {
                        Text("No spend cap on this plan")
                            .font(Typography.tinyLabel)
                            .foregroundStyle(ThemeColors.secondaryLabel)
                    } else if alarm.limitReached {
                        Text("Budget reached")
                            .font(Typography.tinyLabel)
                            .foregroundStyle(ThemeColors.danger)
                    } else if confirmed, let eta = budget.estimatedTimeToExhaustion(now: now) {
                        let runwayText = "~\(DurationFormatter.compact(eta)) to limit"
                        Text(runwayText)
                            .font(Typography.tinyLabel)
                            .foregroundStyle(ThemeColors.caution)
                            .copyable(runwayText)
                            .help("Estimated time until the credit cap at the pace observed this period")
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
