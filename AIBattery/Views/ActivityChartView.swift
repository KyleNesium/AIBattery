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
        case .hourly: return todayHourCounts.values.allSatisfy { $0 == 0 }
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
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
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
                .transition(.opacity)
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
                .transition(.opacity)
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
                .transition(.opacity)
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

    // MARK: - Insight rows (merged from former Insights section)

    private static let insightLabelWidth: CGFloat = 55

    @ViewBuilder
    private func insightRows(_ snapshot: UsageSnapshot) -> some View {
        // Date range
        if let start = snapshot.firstSessionDate,
           let lastDay = snapshot.dailyActivity.last?.date,
           let end = DateFormatters.dateKey.date(from: lastDay) {
            insightRow(
                label: "Period",
                value: DateFormatters.formatDateRange(from: start, to: end),
                tooltip: "Date range of tracked data"
            )
        }

        // Longest session
        if let duration = snapshot.longestSessionDuration, snapshot.longestSessionMessages > 0 {
            insightRow(
                label: "Longest",
                value: "\(duration) \u{00B7} \(snapshot.longestSessionMessages) msgs",
                tooltip: "Longest single session by duration"
            )
        }

        // All Time (at bottom)
        insightRow(
            label: "All Time",
            value: "\(snapshot.totalMessages) msgs \u{00B7} \(snapshot.totalSessions) sessions",
            tooltip: "Cumulative activity across all sessions"
        )
        .accessibilityLabel("All time: \(snapshot.totalMessages) messages, \(snapshot.totalSessions) sessions")
    }

    private func insightRow(
        label: String,
        value: String,
        tooltip: String,
        valueColor: Color = .primary
    ) -> some View {
        HStack {
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(ThemeColors.secondaryLabel)
                .frame(width: Self.insightLabelWidth, alignment: .leading)
                .help(tooltip)
            Spacer()
            Text(value)
                .font(Typography.monoCaption)
                .foregroundStyle(valueColor)
        }
        .copyable("\(label) \u{00B7} \(value)")
        .accessibilityElement(children: .combine)
    }

    // MARK: - Hover helpers

    static let selectionRuleStyle = StrokeStyle(lineWidth: 0.5, dash: [3, 3])

    /// Tooltip label styling.
    func tooltipLabel(_ text: String) -> some View {
        Text(text)
            .font(Typography.monoCaptionSmall)
            .foregroundStyle(ThemeColors.secondaryLabel)
            .padding(.horizontal, Spacing.small)
            .padding(.vertical, Spacing.tight)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
    }

    /// Chart overlay that handles hover detection AND renders the tooltip at the correct X position.
    /// The tooltip is drawn as an overlay child (not a chart annotation), so it never affects chart layout.
    func chartHoverOverlay(
        proxy: ChartProxy,
        tooltipText: String?,
        onHover: @escaping (CGFloat) -> Void,
        onEnd: @escaping () -> Void
    ) -> some View {
        GeometryReader { geo in
            let plotFrame = geo[proxy.plotAreaFrame]
            Rectangle().fill(.clear).contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        onHover(location.x - plotFrame.origin.x)
                    case .ended:
                        onEnd()
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let tooltipText, let hoverX = currentHoverX(proxy: proxy, plotFrame: plotFrame) {
                        tooltipLabel(tooltipText)
                            .offset(x: plotFrame.origin.x + hoverX - 20, y: 2)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    /// Current hover X position within the plot area, derived from selection state.
    func currentHoverX(proxy: ChartProxy, plotFrame: CGRect) -> CGFloat? {
        switch mode {
        case .daily:
            guard let id = selectedDailyId,
                  let point = cachedDaily.first(where: { $0.id == id }),
                  let x = proxy.position(forX: point.date) else { return nil }
            return x
        case .hourly:
            guard let offset = selectedHourlyOffset,
                  let x = proxy.position(forX: offset) else { return nil }
            return x
        case .monthly:
            guard let id = selectedMonthlyId,
                  let point = cachedMonthly.first(where: { $0.id == id }),
                  let x = proxy.position(forX: point.date) else { return nil }
            return x
        }
    }

    /// Tooltip text for the currently hovered point, or nil if nothing selected.
    var hoverTooltipText: String? {
        switch mode {
        case .daily:
            guard let id = selectedDailyId,
                  let point = cachedDaily.first(where: { $0.id == id }) else { return nil }
            return "\(point.count) msgs"
        case .hourly:
            guard let offset = selectedHourlyOffset,
                  let point = cachedHourly.first(where: { $0.id == offset }) else { return nil }
            return "\(Self.formatHourLabel(point.hour)):00 — \(point.count) msgs"
        case .monthly:
            guard let id = selectedMonthlyId,
                  let point = cachedMonthly.first(where: { $0.id == id }) else { return nil }
            return "\(Self.compactCount(point.count)) msgs"
        }
    }

    // MARK: - Formatters

    static func dayShortLabel(_ date: Date) -> String {
        DateFormatters.shortDay.string(from: date)
    }

    static func monthAbbrev(_ date: Date) -> String {
        DateFormatters.shortMonth.string(from: date)
    }

    /// Compact integer counts for chart axes (e.g. 1500 → "2K").
    /// Differs from TokenFormatter which formats fractional token values (e.g. 1500 → "1.5K").
    static func compactCount(_ value: Int) -> String {
        if value >= 1_000_000 {
            let m = Double(value) / 1_000_000
            return m == m.rounded() ? "\(Int(m))M" : String(format: "%.1fM", m)
        }
        if value >= 1_000 {
            let k = Double(value) / 1_000
            if k >= 999.5 { return "1.0M" }
            return k == k.rounded() ? "\(Int(k))K" : String(format: "%.0fK", k)
        }
        return "\(value)"
    }

    private static let hourLabels: [String] = (0..<24).map { String(format: "%02d", $0) }

    static func formatHourLabel(_ hour: Int) -> String {
        guard hour >= 0 && hour < 24 else { return String(format: "%02d", hour) }
        return hourLabels[hour]
    }
}
