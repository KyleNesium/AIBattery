import SwiftUI

struct TokenUsageSection: View {
    let snapshot: UsageSnapshot
    var activeModelId: String?
    @AppStorage(UserDefaultsKeys.tokensCollapsed) private var collapsed: Bool = false

    /// Cached active model index and ordered tokens — avoids linear scan + array allocation per render.
    @State private var cachedActiveIndex: Int? = nil
    @State private var cachedOrdered: [(offset: Int, element: ModelTokenSummary)] = []

    private func recomputeOrdered() {
        let tokens = snapshot.modelTokens
        var activeIdx: Int? = nil
        if let activeId = activeModelId, !activeId.isEmpty {
            activeIdx = tokens.firstIndex(where: { activeId.hasPrefix($0.id) || $0.id.hasPrefix(activeId) })
        }
        cachedActiveIndex = activeIdx
        guard let activeIdx else {
            cachedOrdered = Array(tokens.enumerated())
            return
        }
        var result = [(offset: Int, element: ModelTokenSummary)]()
        result.reserveCapacity(tokens.count)
        result.append((activeIdx, tokens[activeIdx]))
        for (i, model) in tokens.enumerated() where i != activeIdx {
            result.append((i, model))
        }
        cachedOrdered = result
    }

    private func isActive(_ model: ModelTokenSummary) -> Bool {
        guard let activeId = activeModelId, !activeId.isEmpty else { return false }
        return activeId.hasPrefix(model.id) || model.id.hasPrefix(activeId)
    }

    /// Column width for cost values (e.g. "~$12.31").
    private let costColumnWidth: CGFloat = 54
    /// Column width for token values (e.g. "1.2M").
    private let tokenColumnWidth: CGFloat = 42

    /// Aggregate cache hit rate across all models.
    private var overallCacheHitRate: Double? {
        let totalCacheRead = snapshot.modelTokens.reduce(0) { $0 + $1.cacheReadTokens }
        let totalInput = snapshot.modelTokens.reduce(0) { $0 + $1.inputTokens }
        let denominator = totalCacheRead + totalInput
        guard denominator > 0 else { return nil }
        return Double(totalCacheRead) / Double(denominator) * 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerRow

            // Per-model efficiency breakdown
            if !collapsed && !snapshot.modelTokens.isEmpty {
                ForEach(cachedOrdered, id: \.element.id) { _, model in
                    modelRow(model)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onAppear { recomputeOrdered() }
        .onChange(of: snapshot.modelTokens) { _ in recomputeOrdered() }
        .onChange(of: activeModelId) { _ in recomputeOrdered() }
    }

    // MARK: - Header

    private var headerRow: some View {
        let totalTokensText = TokenFormatter.format(snapshot.totalTokens)
        let totalCost = ModelPricing.totalCost(for: snapshot.modelTokens)
        let costText = "~\(ModelPricing.formatCost(totalCost))"
        return HStack {
            CollapsibleSectionHeader(
                title: "Tokens",
                collapsed: $collapsed,
                tooltip: "Total tokens used across all models (cost is API-equivalent estimate)"
            )
            if let rate = overallCacheHitRate {
                Text("\(Int(rate))% cached")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(rate >= 80 ? Color.green : ThemeColors.secondaryLabel)
                    .help("Cache hit rate: cached tokens / (cached + input)")
            }
            Spacer()
            Text(costText)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(ThemeColors.secondaryLabel)
                .frame(width: costColumnWidth, alignment: .trailing)
                .copyable(costText)
            Text(totalTokensText)
                .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.4), value: totalTokensText)
                .frame(width: tokenColumnWidth, alignment: .trailing)
                .copyable(totalTokensText)
        }
    }

    // MARK: - Model row (efficiency layout)

    private func modelRow(_ model: ModelTokenSummary) -> some View {
        let modelTokensText = TokenFormatter.format(model.totalTokens)
        let modelCost: String = {
            guard let pricing = ModelPricing.pricing(for: model.id) else { return "" }
            let cost = pricing.cost(
                input: model.inputTokens,
                output: model.outputTokens,
                cacheRead: model.cacheReadTokens,
                cacheWrite: model.cacheWriteTokens
            )
            return "~\(ModelPricing.formatCost(cost))"
        }()
        let cacheText: String? = {
            guard let rate = model.cacheHitRate else { return nil }
            return "\(Int(rate))% cached"
        }()
        let outputText = "\(TokenFormatter.format(model.outputTokens)) out"

        return VStack(alignment: .leading, spacing: 2) {
            // Model name + total tokens + cost
            HStack(spacing: 6) {
                Text(model.displayName)
                    .font(.caption)
                    .lineLimit(1)

                if isActive(model) {
                    Text("▶")
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .help("Active model in current session")
                        .accessibilityLabel("Active")
                }

                Spacer()

                if !modelCost.isEmpty {
                    Text(modelCost)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(ThemeColors.secondaryLabel)
                        .frame(width: costColumnWidth, alignment: .trailing)
                        .copyable(modelCost)
                }

                Text(modelTokensText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(ThemeColors.secondaryLabel)
                    .frame(width: tokenColumnWidth, alignment: .trailing)
                    .copyable(modelTokensText)
            }

            // Efficiency summary: cache hit rate + output tokens
            HStack(spacing: 8) {
                if let cacheText {
                    Text(cacheText)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(ThemeColors.tertiaryLabel)
                }
                Text(outputText)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(ThemeColors.tertiaryLabel)
            }
            .padding(.leading, 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.displayName), \(modelTokensText) tokens, \(cacheText ?? "no cache"), \(outputText)")
    }
}
