import SwiftUI

// MARK: - Trend summary and cost breakdown

extension InsightsView {

    // MARK: - Trend

    func trendSummary(_ snapshot: UsageSnapshot) -> some View {
        let data = ActivityTrendComputation.compute(mode: mode, snapshot: snapshot, monthTotals: cachedMonthTotals)
        return VStack(spacing: 4) {
            trendRowTop(change: data.change, stat: data.stat)
            trendRowBottom(throttleCount: data.throttleCount, peak: data.peak)
        }
        .padding(.top, 4)
        .copyable(ActivityTrendComputation.copyText(data))
    }

    // MARK: - Shared trend row builders

    func trendRowTop(change: ActivityChangeInfo?, stat: String?) -> some View {
        HStack(spacing: 6) {
            if let change {
                Text(change.symbol)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
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
        HStack(spacing: 6) {
            if throttleCount > 0 {
                Text("Throttled: \(throttleCount)×")
                    .font(Typography.monoCaption)
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
    var costColumnWidth: CGFloat { 54 }
    /// Column width for token values.
    var tokenColumnWidth: CGFloat { 42 }

    /// Model tokens for the current time window.
    var windowedModelTokens: [ModelTokenSummary] {
        guard let snapshot else { return [] }
        switch mode {
        case .hourly: return snapshot.todayModelTokens
        case .daily: return snapshot.weekModelTokens
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
            VStack(alignment: .leading, spacing: 4) {
                ForEach(models) { model in
                    let modelTokensText = TokenFormatter.format(model.totalTokens)
                    let modelCost = "~\(ModelPricing.formatCompactCost(model.estimatedCost))"
                    let copyText = "\(model.displayName) \u{00B7} \(modelCost) \u{00B7} \(modelTokensText)"
                    HStack(spacing: 6) {
                        Text(model.displayName)
                            .font(Typography.tinyLabel)
                            .lineLimit(1)

                        if isActive(model) {
                            Text("▶")
                                .font(Typography.decorativeIcon)
                                .foregroundStyle(.green)
                                .help("Active model in current session")
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
                }
            }
        }
    }
}
