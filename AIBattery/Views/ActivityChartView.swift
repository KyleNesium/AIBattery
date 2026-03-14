import SwiftUI
import Charts

// MARK: - Chart Mode

enum ActivityChartMode: String, CaseIterable {
    case hourly = "24H"
    case daily = "7D"
    case monthly = "12M"
}

// MARK: - View

struct ActivityChartView: View {
    let dailyActivity: [DailyActivity]
    let todayHourCounts: [String: Int]
    var snapshot: UsageSnapshot?
    @AppStorage(UserDefaultsKeys.activityCollapsed) private var collapsed: Bool = false

    @AppStorage(UserDefaultsKeys.chartMode) private var modeRaw: String = ActivityChartMode.hourly.rawValue

    private var mode: ActivityChartMode {
        ActivityChartMode(rawValue: modeRaw) ?? .hourly
    }

    // MARK: - Hover selection state

    @State private var selectedDailyId: String?
    @State private var selectedHourlyOffset: Int?
    @State private var selectedMonthlyId: String?

    // MARK: - Cached data transforms

    /// Cached chart data — recomputed only when source data or mode changes.
    /// Eliminates O(n) transforms from the SwiftUI render path.
    @State private var cachedDaily: [ActivityChartData.DailyPoint] = []
    @State private var cachedHourly: [ActivityChartData.HourlyPoint] = []
    @State private var cachedMonthly: [ActivityChartData.MonthlyPoint] = []
    @State private var cachedMonthTotals: [String: Int] = [:]

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
    private func ensureCachedData(for chartMode: ActivityChartMode, force: Bool = false) {
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
            cachedMonthly = ActivityChartData.monthlyData(from: dailyActivity)
            cachedMonthTotals = ActivityChartData.monthTotals(from: dailyActivity)
            lastMonthlyFingerprint = fp
        }
    }

    /// Single fingerprint combining all data sources — collapses 3 onChange handlers into 1.
    /// When any underlying data changes, the fingerprint changes, triggering one refresh.
    private var dataFingerprint: Int {
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
                    title: "Activity",
                    collapsed: $collapsed,
                    tooltip: "Message activity over time"
                )
                Spacer()
                if collapsed, let snapshot, let change = ActivityTrendComputation.changeVsYesterday(snapshot) {
                    Text(change.symbol)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(change.color)
                    Text(change.label)
                        .font(.system(.caption2, design: .monospaced))
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
                        .font(.system(size: 14))
                        .foregroundStyle(ThemeColors.tertiaryLabel)
                    Text("No activity in \(mode.rawValue) window")
                        .font(.caption2)
                        .foregroundStyle(ThemeColors.tertiaryLabel)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            } else {
                switch mode {
                case .daily:
                    dailyChart
                case .hourly:
                    hourlyChart
                case .monthly:
                    monthlyChart
                }
            }

            // Trend summary + insight rows
            if !collapsed, let snapshot {
                trendSummary(snapshot)
                    .accessibilityElement(children: .combine)
                insightRows(snapshot)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onAppear { refreshCachedData() }
        .onChange(of: dataFingerprint) { _ in refreshCachedData() }
        .onChange(of: modeRaw) { _ in
            selectedDailyId = nil
            selectedHourlyOffset = nil
            selectedMonthlyId = nil
            ensureCachedData(for: mode)
        }
    }

    // MARK: - Shared chart styling

    /// Standard Y-axis for all chart modes: trailing position, 3 ticks, compact count labels.
    private var sharedYAxis: some AxisContent {
        AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
            AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(ThemeColors.tertiaryLabel)
            AxisValueLabel {
                if let v = value.as(Int.self) {
                    Text(Self.compactCount(v))
                        .font(.system(size: 8))
                        .foregroundStyle(ThemeColors.tertiaryLabel)
                }
            }
        }
    }

    // MARK: - Daily Chart (7D)

    private var dailyChart: some View {
        let data = cachedDaily
        let dates = data.map(\.date)
        let total = data.reduce(0) { $0 + $1.count }
        let peak = data.max(by: { $0.count < $1.count })
        let a11yLabel: String = {
            if let peak, peak.count > 0 {
                return "7-day activity chart. \(total) messages this week. Peak: \(peak.count) on \(Self.dayShortLabel(peak.date))"
            }
            return "7-day activity chart. \(total) messages this week"
        }()

        return Chart {
            ForEach(data) { point in
                AreaMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Messages", point.count)
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [ThemeColors.chartAccent.opacity(0.3), ThemeColors.chartAccent.opacity(0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Messages", point.count)
                )
                .foregroundStyle(ThemeColors.chartAccent)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Messages", point.count)
                )
                .foregroundStyle(ThemeColors.chartAccent)
                .symbolSize(12)
            }

            if let selectedId = selectedDailyId,
               let point = data.first(where: { $0.id == selectedId }) {
                RuleMark(x: .value("Selected", point.date, unit: .day))
                    .foregroundStyle(ThemeColors.tertiaryLabel)
                    .lineStyle(Self.selectionRuleStyle)
                    .annotation(position: .top, spacing: 4) {
                        tooltipLabel("\(point.count) msgs")
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: dates) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(Self.dayShortLabel(date))
                            .font(.system(size: 9))
                    }
                }
            }
        }
        .chartYAxis { sharedYAxis }
        .chartPlotStyle { plot in plot.background(.clear) }
        .chartOverlay { proxy in
            chartHoverOverlay(proxy: proxy) { x in
                guard let date: Date = proxy.value(atX: x) else { return }
                let cal = Calendar.current
                selectedDailyId = data
                    .min(by: {
                        abs(cal.dateComponents([.hour], from: $0.date, to: date).hour ?? .max)
                        < abs(cal.dateComponents([.hour], from: $1.date, to: date).hour ?? .max)
                    })?.id
            } onEnd: {
                selectedDailyId = nil
            }
        }
        .frame(height: 50)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
    }

    // MARK: - Hourly Chart (24H)

    private var hourlyChart: some View {
        let data = cachedHourly
        let total = data.reduce(0) { $0 + $1.count }
        let peak = data.max(by: { $0.count < $1.count })
        let a11yLabel: String = {
            if let peak, peak.count > 0 {
                return "24-hour activity chart. \(total) messages in trailing window. Peak hour: \(Self.formatHourLabel(peak.hour)) with \(peak.count) messages"
            }
            return "24-hour activity chart. \(total) messages in trailing window"
        }()

        return Chart {
            ForEach(data) { point in
                AreaMark(
                    x: .value("Hour", point.id),
                    y: .value("Messages", point.count)
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [ThemeColors.chartAccent.opacity(0.3), ThemeColors.chartAccent.opacity(0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Hour", point.id),
                    y: .value("Messages", point.count)
                )
                .foregroundStyle(ThemeColors.chartAccent)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
            }

            if let selectedOffset = selectedHourlyOffset,
               let point = data.first(where: { $0.id == selectedOffset }) {
                RuleMark(x: .value("Selected", point.id))
                    .foregroundStyle(ThemeColors.tertiaryLabel)
                    .lineStyle(Self.selectionRuleStyle)
                    .annotation(position: .top, spacing: 4) {
                        tooltipLabel("\(Self.formatHourLabel(point.hour)):00 — \(point.count) msgs")
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: [0, 4, 8, 12, 16, 20, 23]) { value in
                AxisValueLabel {
                    if let offset = value.as(Int.self), offset >= 0, offset < data.count {
                        Text(Self.formatHourLabel(data[offset].hour))
                            .font(.system(size: 8))
                    }
                }
            }
        }
        .chartXScale(domain: 0...23)
        .chartYAxis { sharedYAxis }
        .chartPlotStyle { plot in plot.background(.clear) }
        .chartOverlay { proxy in
            chartHoverOverlay(proxy: proxy) { x in
                guard let value: Double = proxy.value(atX: x) else { return }
                selectedHourlyOffset = max(0, min(23, Int(value.rounded())))
            } onEnd: {
                selectedHourlyOffset = nil
            }
        }
        .frame(height: 50)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
    }

    // MARK: - Monthly Chart (12M)

    private var monthlyChart: some View {
        let data = cachedMonthly
        let dates = data.map(\.date)
        // Use actual (non-projected) total for accessibility — projected data is only for visual comparison
        let actualTotal = dailyActivity.reduce(0) { $0 + $1.messageCount }
        let a11yLabel = "12-month activity chart. \(actualTotal) messages total"

        return Chart {
            ForEach(data) { point in
                AreaMark(
                    x: .value("Month", point.date, unit: .month),
                    y: .value("Messages", point.count)
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [ThemeColors.chartAccent.opacity(0.3), ThemeColors.chartAccent.opacity(0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Month", point.date, unit: .month),
                    y: .value("Messages", point.count)
                )
                .foregroundStyle(ThemeColors.chartAccent)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Month", point.date, unit: .month),
                    y: .value("Messages", point.count)
                )
                .foregroundStyle(ThemeColors.chartAccent)
                .symbolSize(12)
            }

            if let selectedId = selectedMonthlyId,
               let point = data.first(where: { $0.id == selectedId }) {
                RuleMark(x: .value("Selected", point.date, unit: .month))
                    .foregroundStyle(ThemeColors.tertiaryLabel)
                    .lineStyle(Self.selectionRuleStyle)
                    .annotation(position: .top, spacing: 4) {
                        tooltipLabel("\(Self.compactCount(point.count)) msgs")
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: dates) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(Self.monthAbbrev(date))
                            .font(.system(size: 9))
                    }
                }
            }
        }
        .chartYAxis { sharedYAxis }
        .chartPlotStyle { plot in plot.background(.clear) }
        .chartOverlay { proxy in
            chartHoverOverlay(proxy: proxy) { x in
                guard let date: Date = proxy.value(atX: x) else { return }
                let cal = Calendar.current
                selectedMonthlyId = data
                    .min(by: {
                        abs(cal.dateComponents([.day], from: $0.date, to: date).day ?? .max)
                        < abs(cal.dateComponents([.day], from: $1.date, to: date).day ?? .max)
                    })?.id
            } onEnd: {
                selectedMonthlyId = nil
            }
        }
        .frame(height: 50)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
    }

    // MARK: - Trend

    private func trendSummary(_ snapshot: UsageSnapshot) -> some View {
        let data = ActivityTrendComputation.compute(mode: mode, snapshot: snapshot, monthTotals: cachedMonthTotals)
        return VStack(spacing: 4) {
            trendRowTop(change: data.change, stat: data.stat)
            trendRowBottom(throttleCount: data.throttleCount, peak: data.peak)
        }
        .padding(.top, 4)
        .copyable(ActivityTrendComputation.copyText(data))
    }

    // MARK: - Shared trend row builders

    private func trendRowTop(change: ActivityChangeInfo?, stat: String?) -> some View {
        HStack(spacing: 6) {
            if let change {
                Text(change.symbol)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(change.color)
                Text(change.label)
                    .font(.system(.caption, design: .monospaced, weight: .medium))
                    .foregroundStyle(change.color)
            }
            Spacer()
            if let stat {
                Text(stat)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(ThemeColors.secondaryLabel)
            }
        }
    }

    private func trendRowBottom(throttleCount: Int, peak: String?) -> some View {
        HStack(spacing: 6) {
            if throttleCount > 0 {
                Text("Throttled: \(throttleCount)×")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(ThemeColors.caution)
            } else {
                Text("Throttled: 0×")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(ThemeColors.secondaryLabel)
            }
            Spacer()
            if let peak {
                Text(peak)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(ThemeColors.secondaryLabel)
            }
        }
    }

    // MARK: - Insight rows (merged from former Insights section)

    private static let insightLabelWidth: CGFloat = 55

    @ViewBuilder
    private func insightRows(_ snapshot: UsageSnapshot) -> some View {
        // All Time
        insightRow(
            label: "All Time",
            value: "\(snapshot.totalMessages) msgs \u{00B7} \(snapshot.totalSessions) sessions",
            tooltip: "Cumulative activity across all sessions"
        )
        .accessibilityLabel("All time: \(snapshot.totalMessages) messages, \(snapshot.totalSessions) sessions")

        // Longest session
        if let duration = snapshot.longestSessionDuration, snapshot.longestSessionMessages > 0 {
            insightRow(
                label: "Longest",
                value: "\(duration) \u{00B7} \(snapshot.longestSessionMessages) msgs",
                tooltip: "Longest single session by duration"
            )
        }

        // Date range
        if let start = snapshot.firstSessionDate,
           let lastDay = snapshot.dailyActivity.last?.date,
           let end = DateFormatters.dateKey.date(from: lastDay) {
            insightRow(
                label: "Period",
                value: DateFormatters.formatDateRange(from: start, to: end),
                tooltip: "Date range of tracked data",
                valueColor: ThemeColors.secondaryLabel
            )
        }
    }

    private func insightRow(
        label: String,
        value: String,
        tooltip: String,
        valueColor: Color = .primary
    ) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(ThemeColors.secondaryLabel)
                .frame(width: Self.insightLabelWidth, alignment: .leading)
                .help(tooltip)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(valueColor)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.4), value: value)
                .copyable(value)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Tooltip annotation

    /// Shared tooltip label styling used by all chart hover annotations.
    private func tooltipLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(ThemeColors.secondaryLabel)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
    }

    /// Shared RuleMark styling for hover selection indicators.
    private static let selectionRuleStyle = StrokeStyle(lineWidth: 0.5, dash: [3, 3])

    /// Shared chart overlay that converts mouse location to plot-area X offset.
    /// Eliminates the duplicated GeometryReader + Rectangle + onContinuousHover boilerplate.
    private func chartHoverOverlay(proxy: ChartProxy, onHover: @escaping (CGFloat) -> Void, onEnd: @escaping () -> Void) -> some View {
        GeometryReader { geo in
            Rectangle().fill(.clear).contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let origin = geo[proxy.plotAreaFrame].origin
                        onHover(location.x - origin.x)
                    case .ended:
                        onEnd()
                    }
                }
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
