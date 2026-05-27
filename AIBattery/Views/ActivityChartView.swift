import SwiftUI
import Charts

// MARK: - Chart Mode

enum ActivityChartMode: String, CaseIterable {
    case fiveHour = "5H"
    case sevenDay = "7D"
    case monthly = "12M"
}

// MARK: - View

struct InsightsView: View {
    let dailyActivity: [DailyActivity]
    let todayHourCounts: [String: Int]
    var snapshot: UsageSnapshot?
    var activeModelId: String?
    @AppStorage(UserDefaultsKeys.activityCollapsed) private var collapsed: Bool = true

    @AppStorage(UserDefaultsKeys.chartMode) private var modeRaw: String = ActivityChartMode.fiveHour.rawValue

    var mode: ActivityChartMode {
        ActivityChartMode(rawValue: modeRaw) ?? .fiveHour
    }

    // MARK: - Hover selection state

    @State var selectedDailyId: String?
    @State var selectedFiveHourOffset: Int?
    @State var selectedMonthlyId: String?

    // MARK: - Cached data transforms

    /// Cached chart data — recomputed only when source data or mode changes.
    /// Eliminates O(n) transforms from the SwiftUI render path.
    @State var cachedSevenDay: [ActivityChartData.DailyPoint] = []
    @State var cachedFiveHour: [ActivityChartData.FiveHourPoint] = []
    @State var cachedMonthly: [ActivityChartData.MonthlyPoint] = []
    @State var cachedMonthTotals: [String: Int] = [:]

    /// Per-mode fingerprint to skip recomputation when toggling back to a mode
    /// whose underlying data hasn't changed (e.g. 5H → 7D → 5H).
    @State private var lastFiveHourFingerprint: Int = 0
    @State private var lastSevenDayFingerprint: Int = 0
    @State private var lastMonthlyFingerprint: Int = 0

    /// Recompute cached data for the active mode only. Called from body via .onChange.
    private func refreshCachedData() {
        ensureCachedData(for: mode, force: true)
    }

    /// Lazily compute cached data only for the requested mode.
    /// Skips recomputation if the underlying data fingerprint hasn't changed.
    func ensureCachedData(for chartMode: ActivityChartMode, force: Bool = false) {
        let fp = dataFingerprint
        switch chartMode {
        case .fiveHour:
            guard force || fp != lastFiveHourFingerprint else { return }
            cachedFiveHour = ActivityChartData.fiveHourData(from: snapshot?.fiveHourTokenBuckets ?? [:])
            lastFiveHourFingerprint = fp
        case .sevenDay:
            guard force || fp != lastSevenDayFingerprint else { return }
            cachedSevenDay = ActivityChartData.sevenDayData(from: snapshot?.dailyTokenTotals ?? [:])
            lastSevenDayFingerprint = fp
        case .monthly:
            guard force || fp != lastMonthlyFingerprint else { return }
            let totals = ActivityChartData.monthTokenTotals(from: snapshot?.dailyTokenTotals ?? [:])
            cachedMonthTotals = totals
            cachedMonthly = ActivityChartData.monthlyData(from: totals)
            lastMonthlyFingerprint = fp
        }
    }

    /// Single fingerprint combining all data sources — collapses 3 onChange handlers into 1.
    /// When any underlying data changes, the fingerprint changes, triggering one refresh.
    var dataFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(snapshot?.fiveHourTokens)
        hasher.combine(snapshot?.sevenDayTokens)
        hasher.combine(snapshot?.totalTokens)
        return hasher.finalize()
    }

    /// Whether the chart is loading (no snapshot yet), genuinely empty, or has data.
    enum DisplayState: Equatable { case loading, empty, data }

    /// Pure, testable decision. A nil snapshot means the first refresh hasn't completed
    /// yet — that is `.loading`, NOT `.empty`, so the "No activity" message can't flash
    /// on cold start. Checks source token fields directly (no chart-data recompute).
    static func displayState(snapshot: UsageSnapshot?, mode: ActivityChartMode) -> DisplayState {
        guard let snapshot else { return .loading }
        let tokens: Int = switch mode {
        case .fiveHour: snapshot.fiveHourTokens
        case .sevenDay: snapshot.sevenDayTokens
        case .monthly: snapshot.dailyTokenTotals.values.reduce(0, +)
        }
        return tokens == 0 ? .empty : .data
    }

    private var isLoading: Bool { Self.displayState(snapshot: snapshot, mode: mode) == .loading }
    private var isEmpty: Bool { Self.displayState(snapshot: snapshot, mode: mode) == .empty }

    /// Brief summary shown in the collapsed header when no trend data is available.
    private func collapsedSummary(_ snap: UsageSnapshot) -> String {
        let todayTokens = snap.todayModelTokens.reduce(0) { $0 + $1.totalTokens }
        if todayTokens > 0 {
            return "\(TokenFormatter.format(todayTokens)) today"
        }
        if snap.totalTokens > 0 {
            return "\(TokenFormatter.format(snap.totalTokens)) total"
        }
        return "No activity"
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.gap) {
            // Header with toggle
            HStack {
                CollapsibleSectionHeader(
                    title: "Insights",
                    collapsed: $collapsed,
                    tooltip: "Activity, cost, and usage insights"
                )
                Spacer()
                if collapsed, let snapshot {
                    if let change = ActivityTrendComputation.changeVsYesterday(snapshot) {
                        Text(change.symbol)
                            .font(Typography.trendLabelSmall)
                            .foregroundStyle(change.color)
                        Text(change.label)
                            .font(Typography.monoCaptionSmall)
                            .foregroundStyle(change.color)
                    } else {
                        Text(collapsedSummary(snapshot))
                            .font(Typography.monoCaptionSmall)
                            .foregroundStyle(ThemeColors.secondaryLabel)
                    }
                }
                if !collapsed {
                    Picker("", selection: $modeRaw) {
                        ForEach(ActivityChartMode.allCases, id: \.rawValue) { m in
                            Text(m.rawValue).tag(m.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: Layout.activityModePickerWidth)
                    .scaleEffect(0.8, anchor: .trailing)
                    .accessibilityLabel("Activity time range")
                    .accessibilityHint("Switch between 5 hour, 7 day, and 12 month views")
                    .help("Switch activity chart time range")
                }
            }

            if collapsed {
                // show nothing below header
            } else if isLoading {
                // First refresh hasn't completed — reserve the chart's height without a
                // misleading "No activity" message that would flash on cold start.
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: Layout.chartHeight)
            } else if isEmpty {
                VStack(spacing: Spacing.inner) {
                    Image(systemName: "chart.line.flattrend.xyaxis")
                        .font(Typography.heroTitle)
                        .foregroundStyle(ThemeColors.tertiaryLabel)
                    Text("No activity in \(mode.rawValue) window — start a session to see data")
                        .font(Typography.tinyLabel)
                        .foregroundStyle(ThemeColors.tertiaryLabel)
                }
                .frame(maxWidth: .infinity)
                .frame(height: Layout.chartHeight)
                .transition(MotionConstants.expandTransition)
            } else {
                VStack(alignment: .leading, spacing: Spacing.gap) {
                    switch mode {
                    case .sevenDay:
                        dailyChart
                    case .fiveHour:
                        fiveHourChart
                    case .monthly:
                        monthlyChart
                    }
                }
                .id(mode)
                .transition(.opacity)
                .animation(MotionConstants.standard, value: mode)
            }

            // Trend + cost + history — visually grouped
            if !collapsed, let snapshot {
                VStack(alignment: .leading, spacing: Spacing.gap) {
                    trendSummary(snapshot)
                        .accessibilityElement(children: .combine)

                    if !windowedModelTokens.isEmpty {
                        StyledDivider()
                        costSection(snapshot)
                    }

                    StyledDivider()
                    insightRows(snapshot)
                }
                .transition(MotionConstants.expandTransition)
            }
        }
        .padding(.horizontal, Spacing.sectionHorizontal)
        .padding(.vertical, Spacing.section)
        .onAppear { refreshCachedData() }
        .onChange(of: dataFingerprint) { _ in refreshCachedData() }
        .onChange(of: modeRaw) { _ in
            selectedDailyId = nil
            selectedFiveHourOffset = nil
            selectedMonthlyId = nil
            ensureCachedData(for: mode)
        }
    }
}
