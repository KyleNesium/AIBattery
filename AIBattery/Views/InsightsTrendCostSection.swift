import SwiftUI

// MARK: - Trend summary and cost breakdown

extension InsightsView {
    // MARK: - Trend

    func trendSummary(_ snapshot: UsageSnapshot) -> some View {
        let data = ActivityTrendComputation.compute(mode: mode, snapshot: snapshot, monthTotals: cachedMonthTotals)
        return VStack(spacing: Spacing.inner) {
            trendRowTop(change: data.change, stat: data.stat)
            trendRowBottom(throttleCount: data.throttleCount, peak: data.peak)
        }
        .padding(.top, Spacing.inner)
        .copyable(ActivityTrendComputation.copyText(data))
    }

    // MARK: - Shared trend row builders

    func trendRowTop(change: ActivityChangeInfo?, stat: String?) -> some View {
        HStack(spacing: Spacing.gap) {
            if let change {
                Text(change.symbol)
                    .font(Typography.trendSymbol)
                    .foregroundStyle(change.color)
                Text(change.label)
                    .font(Typography.monoCaption)
                    .foregroundStyle(change.color)
            }
            Spacer()
            if let stat {
                Text(stat)
                    .font(Typography.monoCaption)
                    .foregroundStyle(ThemeColors.secondaryLabel)
            }
        }
    }

    func trendRowBottom(throttleCount: Int, peak: String?) -> some View {
        HStack(spacing: Spacing.gap) {
            if throttleCount > 0 {
                HStack(spacing: Spacing.xsmall) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(Typography.decorativeIcon)
                        .accessibilityHidden(true)
                    Text("Throttled: \(throttleCount)×")
                        .font(Typography.monoCaption)
                }
                .foregroundStyle(ThemeColors.caution)
            } else {
                Text("Throttled: 0×")
                    .font(Typography.monoCaption)
                    .foregroundStyle(ThemeColors.secondaryLabel)
            }
            Spacer()
            if let peak {
                Text(peak)
                    .font(Typography.monoCaption)
                    .foregroundStyle(ThemeColors.secondaryLabel)
            }
        }
    }

    // MARK: - Cost breakdown (mode-aware)

    /// Column width for cost values.
    var costColumnWidth: CGFloat { Layout.costColumn }
    /// Column width for token values.
    var tokenColumnWidth: CGFloat { Layout.tokenColumn }

    /// Model tokens for the current time window.
    var windowedModelTokens: [ModelTokenSummary] {
        guard let snapshot else { return [] }
        switch mode {
        case .fiveHour: return snapshot.todayModelTokens
        case .sevenDay: return snapshot.weekModelTokens
        case .monthly: return snapshot.monthModelTokens
        }
    }

    func isActive(_ model: ModelTokenSummary) -> Bool {
        guard let activeId = activeModelId, !activeId.isEmpty else { return false }
        return activeId.hasPrefix(model.id) || model.id.hasPrefix(activeId)
    }

    @ViewBuilder
    func costSection(_ snapshot: UsageSnapshot) -> some View {
        let models = windowedModelTokens
        if !models.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.inner) {
                ForEach(models) { model in
                    let active = isActive(model)
                    let modelTokensText = TokenFormatter.format(model.totalTokens)
                    let modelCost = "~\(ModelPricing.formatCompactCost(model.estimatedCost))"
                    let activeSuffix = active ? " \u{00B7} active" : ""
                    let copyText = "\(model.displayName)\(activeSuffix) \u{00B7} \(modelCost) \u{00B7} \(modelTokensText)"
                    HStack(spacing: Spacing.gap) {
                        Text(model.displayName)
                            .font(Typography.tinyLabel)
                            .lineLimit(1)

                        if active {
                            Text("▶")
                                .font(Typography.decorativeIcon)
                                .foregroundStyle(ThemeColors.success)
                                .help("Active model in current session")
                                .accessibilityLabel("Active model")
                        }

                        Spacer()

                        Text(modelCost)
                            .font(Typography.monoCaptionSmall)
                            .foregroundStyle(ThemeColors.tertiaryLabel)
                            .frame(width: costColumnWidth, alignment: .trailing)

                        Text(modelTokensText)
                            .font(Typography.monoCaptionSmall)
                            .foregroundStyle(ThemeColors.tertiaryLabel)
                            .frame(width: tokenColumnWidth, alignment: .trailing)
                    }
                    .copyable(copyText)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(model.displayName)\(active ? ", active" : ""), \(modelCost), \(modelTokensText) tokens")
                }
            }
        }
    }
}
