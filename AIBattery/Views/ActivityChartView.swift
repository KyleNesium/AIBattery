import SwiftUI
import Charts

// MARK: - Chart Mode

enum ActivityChartMode: String, CaseIterable {
    case hourly = "24H"
    case daily = "7D"
    case monthly = "12M"
}

// MARK: - View

struct InsightsView: View {
    let dailyActivity: [DailyActivity]
    let todayHourCounts: [String: Int]
    var snapshot: UsageSnapshot?
    var activeModelId: String?
    @AppStorage(UserDefaultsKeys.activityCollapsed) private var collapsed: Bool = true

    @AppStorage(UserDefaultsKeys.chartMode) private var modeRaw: String = ActivityChartMode.hourly.rawValue

    var mode: ActivityChartMode {
        ActivityChartMode(rawValue: modeRaw) ?? .hourly
    }

    // MARK: - Hover selection state

    @State var selectedDailyId: String?
    @State var selectedHourlyOffset: Int?
    @State var selectedMonthlyId: String?

    // MARK: - Cached data transforms

    /// Cached chart data — recomputed only when source data or mode changes.
    /// Eliminates O(n) transforms from the SwiftUI render path.
    @State var cachedDaily: [ActivityChartData.DailyPoint] = []
    @State var cachedHourly: [ActivityChartData.HourlyPoint] = []
    @State var cachedMonthly: [ActivityChartData.MonthlyPoint] = []
    @State var cachedMonthTotals: [String: Int] = [:]

    /// Per-mode fingerprint to skip recomputation when toggling back to a mode
    /// whose underlying data hasn't changed (e.g. 24H → 7D → 24H).
    @State private var lastHourlyFingerprint: Int = 0
    @State private var lastDailyFingerprint: Int = 0
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
        case .hourly:
            guard force || fp != lastHourlyFingerprint else { return }
            cachedHourly = ActivityChartData.hourlyData(from: todayHourCounts)
            lastHourlyFingerprint = fp
        case .daily:
            guard force || fp != lastDailyFingerprint else { return }
            cachedDaily = ActivityChartData.dailyData(from: dailyActivity)
            lastDailyFingerprint = fp
        case .monthly:
            guard force || fp != lastMonthlyFingerprint else { return }
            let totals = ActivityChartData.monthTotals(from: dailyActivity)
            cachedMonthTotals = totals
            cachedMonthly = ActivityChartData.monthlyData(from: dailyActivity, monthTotals: totals)
            lastMonthlyFingerprint = fp
        }
    }

    /// Single fingerprint combining all data sources — collapses 3 onChange handlers into 1.
    /// When any underlying data changes, the fingerprint changes, triggering one refresh.
    var dataFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(dailyActivity.count)
        hasher.combine(snapshot?.totalMessages)
        hasher.combine(todayHourCounts.values.reduce(0, +))
        return hasher.finalize()
    }

    /// Check source data directly — avoids recomputing chart data just for an emptiness check.
    private var isEmpty: Bool {
        switch mode {
        case .daily: return dailyActivity.allSatisfy { $0.messageCount == 0 }
        case .hourly: return Self.isHourlyEmpty(todayHourCounts: todayHourCounts, dailyActivity: dailyActivity)
        case .monthly: return dailyActivity.allSatisfy { $0.messageCount == 0 }
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header with toggle
            HStack {
                CollapsibleSectionHeader(
                    title: "Insights",
                    collapsed: $collapsed,
                    tooltip: "Activity, cost, and usage insights"
                )
                Spacer()
                if collapsed, let snapshot, let change = ActivityTrendComputation.changeVsYesterday(snapshot) {
                    Text(change.symbol)
                        .font(Typography.trendLabelSmall)
                        .foregroundStyle(change.color)
                    Text(change.label)
                        .font(Typography.monoCaptionSmall)
                        .foregroundStyle(change.color)
                }
                if !collapsed {
                    Picker("", selection: $modeRaw) {
                        ForEach(ActivityChartMode.allCases, id: \.rawValue) { m in
                            Text(m.rawValue).tag(m.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                    .scaleEffect(0.8, anchor: .trailing)
                    .accessibilityLabel("Activity time range")
                    .accessibilityHint("Switch between 24 hour, 7 day, and 12 month views")
                    .help("Switch activity chart time range")
                }
            }

            if collapsed {
                // show nothing below header
            } else if isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "chart.line.flattrend.xyaxis")
                        .font(Typography.heroTitle)
                        .foregroundStyle(ThemeColors.tertiaryLabel)
                    Text("No activity in \(mode.rawValue) window")
                        .font(Typography.tinyLabel)
                        .foregroundStyle(ThemeColors.tertiaryLabel)
                }
                .frame(maxWidth: .infinity)
                .frame(height: Layout.chartHeight)
                .transition(MotionConstants.expandTransition)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                switch mode {
                case .daily:
                    dailyChart
                case .hourly:
                    hourlyChart
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
                VStack(alignment: .leading, spacing: 6) {
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
            selectedHourlyOffset = nil
            selectedMonthlyId = nil
            ensureCachedData(for: mode)
        }
    }
}
