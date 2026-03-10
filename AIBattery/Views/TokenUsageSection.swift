import SwiftUI

struct TokenUsageSection: View {
    let snapshot: UsageSnapshot
    var activeModelId: String?
    @AppStorage(UserDefaultsKeys.showCostEstimate) private var showCost: Bool = false
    @AppStorage(UserDefaultsKeys.tokensCollapsed) private var collapsed: Bool = false

    private let modelIcons = [
        "cpu", "bolt", "sparkles", "cube", "wand.and.stars"
    ]

    /// Sort: active model first, then by total tokens descending.
    private var sortedTokens: [ModelTokenSummary] {
        guard let activeId = activeModelId, !activeId.isEmpty else {
            return snapshot.modelTokens
        }
        var sorted = snapshot.modelTokens
        if let idx = sorted.firstIndex(where: { activeId.hasPrefix($0.id) || $0.id.hasPrefix(activeId) }) {
            let active = sorted.remove(at: idx)
            sorted.insert(active, at: 0)
        }
        return sorted
    }

    private func isActive(_ model: ModelTokenSummary) -> Bool {
        guard let activeId = activeModelId, !activeId.isEmpty else { return false }
        return activeId.hasPrefix(model.id) || model.id.hasPrefix(activeId)
    }

    /// Column width for cost values (e.g. "$12.31").
    private let costColumnWidth: CGFloat = 48
    /// Column width for token values (e.g. "1.2M").
    private let tokenColumnWidth: CGFloat = 42

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: total tokens + optional cost (right-aligned columns)
            headerRow

            // Per-model breakdown with token types underneath
            if !collapsed && !snapshot.modelTokens.isEmpty {
                ForEach(Array(sortedTokens.enumerated()), id: \.element.id) { index, model in
                    modelRow(model, index: index)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Header

    private var headerRow: some View {
        let totalTokensText = TokenFormatter.format(snapshot.totalTokens)
        let costText: String? = showCost ? ModelPricing.formatCost(ModelPricing.totalCost(for: snapshot.modelTokens)) : nil
        let copyText = [costText, totalTokensText].compactMap { $0 }.joined(separator: " · ")

        return HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { collapsed.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(collapsed ? 0 : 90))
                        .foregroundStyle(ThemeColors.tertiaryLabel)
                    Text("Tokens")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Total tokens used across all models")
            .accessibilityHint(collapsed ? "Double-tap to expand" : "Double-tap to collapse")
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
            return ModelPricing.formatCost(cost)
        }()
        let copyText = ([model.displayName, modelCostText, modelTokensText].compactMap { $0 }).joined(separator: " · ")

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
