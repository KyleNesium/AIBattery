import SwiftUI

struct ProjectUsageSection: View {
    let snapshot: UsageSnapshot
    @AppStorage(UserDefaultsKeys.projectsCollapsed) private var collapsed: Bool = false
    @State private var showAll = false
    @State private var searchText = ""
    @State private var sortMode: ProjectSortMode = .tokensDesc
    /// Cached sorted list — avoids O(n log n) sort on every body evaluation.
    @State private var cachedSorted: [ProjectTokenSummary] = []

    private static let defaultLimit = 5
    private static let expandedLimit = 10

    /// Column width for compact cost values (e.g. "~$18").
    private let costColumnWidth: CGFloat = 38
    /// Column width for token values (e.g. "1.2M").
    private let tokenColumnWidth: CGFloat = 42

    private func recomputeSorted() {
        switch sortMode {
        case .tokensDesc:
            cachedSorted = snapshot.projectTokens // already sorted by totalTokens desc
        case .costDesc:
            cachedSorted = snapshot.projectTokens.sorted { $0.estimatedCost > $1.estimatedCost }
        case .costAsc:
            cachedSorted = snapshot.projectTokens.sorted { $0.estimatedCost < $1.estimatedCost }
        case .name:
            cachedSorted = snapshot.projectTokens.sorted { $0.projectName.localizedCaseInsensitiveCompare($1.projectName) == .orderedAscending }
        }
    }

    private var displayedProjects: [ProjectTokenSummary] {
        let sorted = cachedSorted

        if showAll && !searchText.isEmpty {
            let query = searchText.lowercased()
            return sorted.filter { $0.projectName.lowercased().contains(query) }
        }

        let limit = showAll ? Self.expandedLimit : Self.defaultLimit
        return Array(sorted.prefix(limit))
    }

    private var hasMore: Bool {
        snapshot.projectTokens.count > Self.defaultLimit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerRow

            if !collapsed && !snapshot.projectTokens.isEmpty {
                // Search field when expanded
                if showAll {
                    searchField
                }

                ForEach(Array(displayedProjects.enumerated()), id: \.element.id) { index, project in
                    projectRow(project, index: index)
                }

                // Combined controls row: show more/less + sort
                if hasMore || snapshot.projectTokens.count > 1 {
                    controlsRow
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onAppear { recomputeSorted() }
        .onChange(of: sortMode) { _ in recomputeSorted() }
        .onChange(of: snapshot.projectTokens) { _ in recomputeSorted() }
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
        let totalTokensText = TokenFormatter.format(snapshot.totalProjectTokens)
        let costText = "~\(ModelPricing.formatCompactCost(snapshot.totalProjectCost))"
        return HStack {
            CollapsibleSectionHeader(
                title: "Projects",
                collapsed: $collapsed,
                tooltip: "Token usage grouped by project directory (recent sessions)"
            )
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

    // MARK: - Controls row (show more/less + sort on same line)

    private var controlsRow: some View {
        HStack {
            if hasMore {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAll.toggle()
                        if !showAll { searchText = "" }
                    }
                }) {
                    Text(showAll ? "Show less" : "Show more")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(ThemeColors.chartAccent)
                .accessibilityLabel(showAll ? "Show fewer projects" : "Show more projects")
            }

            Spacer()

            if snapshot.projectTokens.count > 1 {
                Button(action: { sortMode = sortMode.next }) {
                    HStack(spacing: 3) {
                        Image(systemName: sortMode.icon)
                            .font(.system(size: 8))
                        Text(sortMode.label)
                            .font(.caption2)
                    }
                }
                .buttonStyle(.plain)
                .fixedSize()
                .foregroundStyle(ThemeColors.tertiaryLabel)
                .help("Cycle sort: \(sortMode.next.label)")
                .accessibilityLabel("Sort by \(sortMode.label)")
            }
        }
    }

    // MARK: - Project row

    private func projectRow(_ project: ProjectTokenSummary, index: Int) -> some View {
        let tokensText = TokenFormatter.format(project.totalTokens)
        let costText = "~\(ModelPricing.formatCompactCost(project.estimatedCost))"
        let copyText = "\(project.projectName) \u{00B7} \(costText) \u{00B7} \(tokensText)"
        return HStack(spacing: 6) {
            Text("\(index + 1)")
                .font(.system(.caption2, design: .monospaced, weight: .medium))
                .foregroundStyle(ThemeColors.tertiaryLabel)
                .frame(width: 14, alignment: .trailing)

            Text(project.projectName)
                .font(.caption)
                .lineLimit(1)

            Spacer()

            Text(costText)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(ThemeColors.tertiaryLabel)
                .frame(width: costColumnWidth, alignment: .trailing)

            Text(tokensText)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(ThemeColors.secondaryLabel)
                .frame(width: tokenColumnWidth, alignment: .trailing)
        }
        .copyable(copyText)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(project.projectName), \(tokensText) tokens")
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
        guard let idx = all.firstIndex(of: self) else { return .tokensDesc }
        return all[(idx + 1) % all.count]
    }
}
