import SwiftUI

struct ProjectUsageSection: View {
    let snapshot: UsageSnapshot
    @AppStorage(UserDefaultsKeys.showCostEstimate) private var showCost: Bool = false
    @AppStorage(UserDefaultsKeys.projectsCollapsed) private var collapsed: Bool = false
    @State private var showAll = false
    @State private var searchText = ""
    @State private var sortMode: ProjectSortMode = .tokensDesc

    /// Minimum projects shown when collapsed.
    private static let collapsedLimit = 6

    /// Expanded limit based on screen height so the panel doesn't overflow.
    private var expandedLimit: Int {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 900
        let rowHeight: CGFloat = 22
        let reservedHeight: CGFloat = 300 // activity chart + insights + footer + dividers
        let maxRows = Int((screenHeight - reservedHeight) / rowHeight)
        return max(maxRows, Self.collapsedLimit)
    }

    /// Column width for compact cost values (e.g. "~$18").
    private let costColumnWidth: CGFloat = 38
    /// Column width for token values (e.g. "1.2M").
    private let tokenColumnWidth: CGFloat = 42

    private var sortedProjects: [ProjectTokenSummary] {
        switch sortMode {
        case .tokensDesc:
            return snapshot.projectTokens // already sorted by totalTokens desc
        case .costDesc:
            return snapshot.projectTokens.sorted { $0.estimatedCost > $1.estimatedCost }
        case .costAsc:
            return snapshot.projectTokens.sorted { $0.estimatedCost < $1.estimatedCost }
        case .name:
            return snapshot.projectTokens.sorted { $0.projectName.localizedCaseInsensitiveCompare($1.projectName) == .orderedAscending }
        }
    }

    private var displayedProjects: [ProjectTokenSummary] {
        let sorted = sortedProjects

        if showAll && !searchText.isEmpty {
            let query = searchText.lowercased()
            return sorted.filter { $0.projectName.lowercased().contains(query) }
        }

        if showAll {
            return Array(sorted.prefix(expandedLimit))
        }

        return Array(sorted.prefix(Self.collapsedLimit))
    }

    private var hasMore: Bool {
        snapshot.projectTokens.count > Self.collapsedLimit
    }

    /// Whether expanded view is capped below total project count.
    private var isCapped: Bool {
        snapshot.projectTokens.count > expandedLimit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerRow

            if !collapsed && !snapshot.projectTokens.isEmpty {
                // Sort + controls row
                if snapshot.projectTokens.count > 1 {
                    controlsRow
                }

                // Search field above list when expanded
                if showAll && hasMore {
                    searchField
                }

                ForEach(Array(displayedProjects.enumerated()), id: \.element.id) { index, project in
                    projectRow(project, index: index)
                }

                if hasMore {
                    expandToggle
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onChange(of: collapsed) { isCollapsed in
            if isCollapsed {
                showAll = false
                searchText = ""
            }
        }
        .onDisappear {
            showAll = false
            searchText = ""
        }
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

    // MARK: - Controls row (sort menu)

    private var controlsRow: some View {
        HStack(spacing: 4) {
            Spacer()
            Button(action: { sortMode = sortMode.next }) {
                HStack(spacing: 3) {
                    Image(systemName: sortMode.icon)
                        .font(.system(size: 8))
                    Text(sortMode.label)
                        .font(.system(.caption2))
                }
            }
            .buttonStyle(.plain)
            .fixedSize()
            .foregroundStyle(ThemeColors.tertiaryLabel)
            .help("Cycle sort: \(sortMode.next.label)")
            .accessibilityLabel("Sort by \(sortMode.label), tap to switch to \(sortMode.next.label)")
        }
    }

    // MARK: - Project row

    private func projectRow(_ project: ProjectTokenSummary, index: Int) -> some View {
        let tokensText = TokenFormatter.format(project.totalTokens)
        let costText: String? = showCost ? "~\(ModelPricing.formatCompactCost(project.estimatedCost))" : nil
        return HStack(spacing: 6) {
            Text("\(index + 1)")
                .font(.system(.caption2, design: .monospaced, weight: .medium))
                .foregroundStyle(ThemeColors.tertiaryLabel)
                .frame(width: 14, alignment: .trailing)

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
        let total = snapshot.projectTokens.count
        let expandLabel: String = isCapped
            ? "Show top \(expandedLimit)"
            : "Show all (\(total))"
        let collapseLabel = "Show less"
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
                    Text(showAll ? collapseLabel : expandLabel)
                        .font(.caption2)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(ThemeColors.tertiaryLabel)
            .help(showAll ? "Show top \(Self.collapsedLimit)" : "\(total - Self.collapsedLimit) more project\(total - Self.collapsedLimit == 1 ? "" : "s")")
            .accessibilityLabel(showAll ? "Show fewer projects" : expandLabel)
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
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(ThemeColors.tertiaryLabel)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.primary.opacity(0.05))
        )
    }
}

// MARK: - Sort mode

private enum ProjectSortMode: CaseIterable {
    case tokensDesc
    case costDesc
    case costAsc
    case name

    var label: String {
        switch self {
        case .tokensDesc: return "tokens"
        case .costDesc: return "cost ↓"
        case .costAsc: return "cost ↑"
        case .name: return "name"
        }
    }

    var icon: String {
        switch self {
        case .tokensDesc: return "arrow.down"
        case .costDesc: return "arrow.down"
        case .costAsc: return "arrow.up"
        case .name: return "textformat.abc"
        }
    }

    var next: ProjectSortMode {
        let all = Self.allCases
        let idx = all.firstIndex(of: self)!
        return all[(idx + 1) % all.count]
    }
}
