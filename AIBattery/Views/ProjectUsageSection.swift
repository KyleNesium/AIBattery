import SwiftUI

struct ProjectUsageSection: View {
    let snapshot: UsageSnapshot
    @AppStorage(UserDefaultsKeys.showCostEstimate) private var showCost: Bool = false
    @AppStorage(UserDefaultsKeys.projectsCollapsed) private var collapsed: Bool = false

    private let projectIcons = [
        "folder", "hammer", "terminal", "doc.text", "gearshape.2"
    ]

    /// Column width for cost values (e.g. "$12.31").
    private let costColumnWidth: CGFloat = 48
    /// Column width for token values (e.g. "1.2M").
    private let tokenColumnWidth: CGFloat = 42

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerRow

            if !collapsed && !snapshot.projectTokens.isEmpty {
                ForEach(Array(snapshot.projectTokens.enumerated()), id: \.element.id) { index, project in
                    projectRow(project, index: index)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Header

    private var headerRow: some View {
        let totalTokens = snapshot.projectTokens.reduce(0) { $0 + $1.totalTokens }
        let totalTokensText = TokenFormatter.format(totalTokens)
        let totalCost = snapshot.projectTokens.reduce(0.0) { $0 + $1.estimatedCost }
        let costText: String? = showCost ? ModelPricing.formatCost(totalCost) : nil
        return HStack {
            CollapsibleSectionHeader(
                title: "Projects",
                collapsed: $collapsed,
                tooltip: "Token usage grouped by project directory (recent sessions)"
            )
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

    // MARK: - Project row

    private func projectRow(_ project: ProjectTokenSummary, index: Int) -> some View {
        let tokensText = TokenFormatter.format(project.totalTokens)
        let costText: String? = showCost ? ModelPricing.formatCost(project.estimatedCost) : nil
        return HStack(spacing: 6) {
            Image(systemName: projectIcons[index % projectIcons.count])
                .font(.system(size: 10))
                .foregroundStyle(ThemeColors.secondaryLabel)
                .frame(width: 14)

            Text(project.projectName)
                .font(.caption)
                .lineLimit(1)

            Spacer()

            if let costText {
                Text(costText)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(ThemeColors.secondaryLabel)
                    .frame(width: costColumnWidth, alignment: .trailing)
                    .copyable(costText)
            }

            Text(tokensText)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(ThemeColors.secondaryLabel)
                .frame(width: tokenColumnWidth, alignment: .trailing)
                .copyable(tokensText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(project.projectName), \(tokensText) tokens")
    }
}
