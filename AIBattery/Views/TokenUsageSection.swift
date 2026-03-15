import SwiftUI

struct TokenUsageSection: View {
    let snapshot: UsageSnapshot
    var activeModelId: String?
    @AppStorage(UserDefaultsKeys.showCostEstimate) private var showCost: Bool = false
    @AppStorage(UserDefaultsKeys.tokensCollapsed) private var collapsed: Bool = false

    private let modelIcons = [
        "cpu", "bolt", "sparkles", "cube", "wand.and.stars"
    ]

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

    /// Active model display name for collapsed summary (e.g. "Opus 4.6").
    private var activeModelName: String? {
        guard let idx = cachedActiveIndex else { return nil }
        return snapshot.modelTokens[idx].displayName
    }

    /// Column width for cost values (e.g. "~$12.31").
    private let costColumnWidth: CGFloat = 54
    /// Column width for token values (e.g. "1.2M").
    private let tokenColumnWidth: CGFloat = 42

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: total tokens + optional cost (right-aligned columns)
            headerRow

            // Per-model breakdown with token types underneath
            if !collapsed && !snapshot.modelTokens.isEmpty {
                ForEach(cachedOrdered, id: \.element.id) { index, model in
                    modelRow(model, index: index)
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
        let costText: String? = showCost ? "~\(ModelPricing.formatCost(totalCost))" : nil
        return HStack {
            CollapsibleSectionHeader(
                title: "Token Usage",
                collapsed: $collapsed,
                tooltip: "Total tokens used across all models (cost is API-equivalent estimate)"
            )
            if collapsed, let activeModel = activeModelName {
                Text(activeModel)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(ThemeColors.tertiaryLabel)
                    .lineLimit(1)
            }
            Spacer()
            if let costText {
                Text(costText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(ThemeColors.secondaryLabel)
                    .frame(width: costColumnWidth, alignment: .trailing)
                    .copyable(costText)
            }
            Text(totalTokensText)
                .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.4), value: totalTokensText)
                .frame(width: tokenColumnWidth, alignment: .trailing)
                .copyable(totalTokensText)
        }
    }

    // MARK: - Model row

    private func modelRow(_ model: ModelTokenSummary, index: Int) -> some View {
        let modelTokensText = TokenFormatter.format(model.totalTokens)
        let modelCostText: String? = {
            guard showCost, let pricing = ModelPricing.pricing(for: model.id) else { return nil }
            let cost = pricing.cost(
                input: model.inputTokens,
                output: model.outputTokens,
                cacheRead: model.cacheReadTokens,
                cacheWrite: model.cacheWriteTokens
            )
            return "~\(ModelPricing.formatCost(cost))"
        }()
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: modelIcons[index % modelIcons.count])
                    .font(.system(size: 10))
                    .foregroundStyle(ThemeColors.secondaryLabel)
                    .frame(width: 14)

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

                if let modelCostText {
                    Text(modelCostText)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(ThemeColors.secondaryLabel)
                        .frame(width: costColumnWidth, alignment: .trailing)
                        .copyable(modelCostText)
                }

                Text(modelTokensText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(ThemeColors.secondaryLabel)
                    .frame(width: tokenColumnWidth, alignment: .trailing)
                    .copyable(modelTokensText)
            }

            // Token type breakdown for this model
            HStack(spacing: 10) {
                Spacer()
                    .frame(width: 14)
                TokenTag(icon: "arrow.up", label: TokenFormatter.format(model.inputTokens), accessibilityName: "input", tooltip: "Input tokens sent to Claude")
                TokenTag(icon: "arrow.down", label: TokenFormatter.format(model.outputTokens), accessibilityName: "output", tooltip: "Output tokens generated by Claude")
                TokenTag(icon: "doc.on.doc", label: TokenFormatter.format(model.cacheReadTokens), accessibilityName: "cache read", tooltip: "Cached tokens reused (cheaper)")
                TokenTag(icon: "square.and.pencil", label: TokenFormatter.format(model.cacheWriteTokens), accessibilityName: "cache write", tooltip: "Tokens written to prompt cache")
                Spacer()
            }
            .lightCopyable("\(TokenFormatter.format(model.inputTokens)) in · \(TokenFormatter.format(model.outputTokens)) out · \(TokenFormatter.format(model.cacheReadTokens)) cache read · \(TokenFormatter.format(model.cacheWriteTokens)) cache write")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.displayName), \(modelTokensText) tokens: \(TokenFormatter.format(model.inputTokens)) input, \(TokenFormatter.format(model.outputTokens)) output, \(TokenFormatter.format(model.cacheReadTokens)) cache read, \(TokenFormatter.format(model.cacheWriteTokens)) cache write")
    }
}

private struct TokenTag: View {
    let icon: String
    let label: String
    var accessibilityName: String = ""
    var tooltip: String = ""

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 8))
                .foregroundStyle(ThemeColors.tertiaryLabel)
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(ThemeColors.tertiaryLabel)
        }
        .accessibilityLabel("\(accessibilityName) \(label)")
        .help(tooltip)
    }
}
