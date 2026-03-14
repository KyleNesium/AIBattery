import SwiftUI

struct ProjectUsageSection: View {
    let snapshot: UsageSnapshot
    @AppStorage(UserDefaultsKeys.showCostEstimate) private var showCost: Bool = false
    @AppStorage(UserDefaultsKeys.projectsCollapsed) private var collapsed: Bool = false
    @State private var showAll = false
    @State private var searchText = ""
    @State private var sortByCost = false

    private let projectIcons = [
        "folder", "hammer", "terminal", "doc.text", "gearshape.2"
    ]

    /// Maximum projects shown before "Show all" toggle.
    private static let visibleLimit = 6

    /// Column width for compact cost values (e.g. "$18").
    private let costColumnWidth: CGFloat = 38
    /// Column width for token values (e.g. "1.2M").
    private let tokenColumnWidth: CGFloat = 42

    /// Projects sorted and filtered based on current state.
    private var displayedProjects: [ProjectTokenSummary] {
        let sorted: [ProjectTokenSummary]
        if sortByCost {
            sorted = snapshot.projectTokens.sorted { $0.estimatedCost > $1.estimatedCost }
        } else {
            sorted = snapshot.projectTokens // already sorted by totalTokens desc
        }

        if showAll && !searchText.isEmpty {
            let query = searchText.lowercased()
            return sorted.filter { $0.projectName.lowercased().contains(query) }
        }

        if !showAll {
            return Array(sorted.prefix(Self.visibleLimit))
        }

        return sorted
    }

    private var hasMore: Bool {
        snapshot.projectTokens.count > Self.visibleLimit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerRow

            if !collapsed && !snapshot.projectTokens.isEmpty {
                // Sort toggle (only when expanded and has multiple projects)
                if snapshot.projectTokens.count > 1 {
                    sortToggle
                }

                ForEach(Array(displayedProjects.enumerated()), id: \.element.id) { index, project in
                    projectRow(project, index: index)
                }

                if hasMore {
                    expandToggle
                }

                // Search field when expanded and has many projects
                if showAll && snapshot.projectTokens.count > Self.visibleLimit {
                    searchField
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
        let costText: String? = showCost ? "~\(ModelPricing.formatCompactCost(totalCost))" : nil
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

    // MARK: - Sort toggle

    private var sortToggle: some View {
        HStack(spacing: 4) {
            Spacer()
            Button(action: { sortByCost.toggle() }) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 8))
                    Text(sortByCost ? "by cost" : "by tokens")
                        .font(.system(.caption2))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(ThemeColors.tertiaryLabel)
            .help("Toggle sort order")
            .accessibilityLabel("Sort \(sortByCost ? "by cost" : "by tokens")")
        }
    }

    // MARK: - Project row

    private func projectRow(_ project: ProjectTokenSummary, index: Int) -> some View {
        let tokensText = TokenFormatter.format(project.totalTokens)
        let costText: String? = showCost ? "~\(ModelPricing.formatCompactCost(project.estimatedCost))" : nil
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
                    .foregroundStyle(ThemeColors.tertiaryLabel)
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

    // MARK: - Expand / collapse toggle

    private var expandToggle: some View {
        let hiddenCount = snapshot.projectTokens.count - Self.visibleLimit
        return HStack {
            Spacer()
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showAll.toggle()
                    if !showAll { searchText = "" }
                }
            }) {
                HStack(spacing: 3) {
                    Image(systemName: showAll ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                    Text(showAll ? "Show less" : "Show all (\(snapshot.projectTokens.count))")
                        .font(.caption2)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(ThemeColors.tertiaryLabel)
            .help(showAll ? "Show top \(Self.visibleLimit)" : "\(hiddenCount) more project\(hiddenCount == 1 ? "" : "s")")
            .accessibilityLabel(showAll ? "Show fewer projects" : "Show all \(snapshot.projectTokens.count) projects")
            Spacer()
        }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 9))
                .foregroundStyle(ThemeColors.tertiaryLabel)
            TextField("Filter projects", text: $searchText)
                .font(.caption)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.primary.opacity(0.05))
        )
    }
}
