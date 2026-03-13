import SwiftUI
import Charts

// MARK: - Chart Mode

enum ActivityChartMode: String, CaseIterable {
    case hourly = "12H"
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

    /// Recompute cached data for the active mode only. Called from body via .onChange.
    private func refreshCachedData() {
        ensureCachedData(for: mode)
    }

    /// Lazily compute cached data only for the requested mode.
    private func ensureCachedData(for chartMode: ActivityChartMode) {
        switch chartMode {
        case .hourly:
            cachedHourly = ActivityChartData.hourlyData(from: todayHourCounts)
        case .daily:
            cachedDaily = ActivityChartData.dailyData(from: dailyActivity)
        case .monthly:
            cachedMonthly = ActivityChartData.monthlyData(from: dailyActivity)
            cachedMonthTotals = ActivityChartData.monthTotals(from: dailyActivity)
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
                if collapsed, let snapshot, let change = changeVsYesterday(snapshot) {
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
                    .accessibilityHint("Switch between 12 hour, 7 day, and 12 month views")
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

            // Trend summary
            if !collapsed, let snapshot {
                trendSummary(snapshot)
                    .accessibilityElement(children: .combine)
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
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            let origin = geo[proxy.plotAreaFrame].origin
                            let x = location.x - origin.x
                            if let date: Date = proxy.value(atX: x) {
                                let cal = Calendar.current
                                selectedDailyId = data
                                    .min(by: {
                                        abs(cal.dateComponents([.hour], from: $0.date, to: date).hour ?? .max)
                                        < abs(cal.dateComponents([.hour], from: $1.date, to: date).hour ?? .max)
                                    })?.id
                            }
                        case .ended:
                            selectedDailyId = nil
                        }
                    }
            }
        }
        .frame(height: 50)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
    }

    // MARK: - Hourly Chart (12H)

    private var hourlyChart: some View {
        let data = cachedHourly
        let total = data.reduce(0) { $0 + $1.count }
        let peak = data.max(by: { $0.count < $1.count })
        let a11yLabel: String = {
            if let peak, peak.count > 0 {
                return "12-hour activity chart. \(total) messages in trailing window. Peak hour: \(Self.formatHourLabel(peak.hour)) with \(peak.count) messages"
            }
            return "12-hour activity chart. \(total) messages in trailing window"
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
            AxisMarks(values: [0, 3, 6, 9, 11]) { value in
                AxisValueLabel {
                    if let offset = value.as(Int.self), offset >= 0, offset < data.count {
                        Text(Self.formatHourLabel(data[offset].hour))
                            .font(.system(size: 8))
                    }
                }
            }
        }
        .chartXScale(domain: 0...11)
        .chartYAxis { sharedYAxis }
        .chartPlotStyle { plot in plot.background(.clear) }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            let origin = geo[proxy.plotAreaFrame].origin
                            let x = location.x - origin.x
                            if let value: Double = proxy.value(atX: x) {
                                selectedHourlyOffset = max(0, min(11, Int(value.rounded())))
                            }
                        case .ended:
                            selectedHourlyOffset = nil
                        }
                    }
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
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            let origin = geo[proxy.plotAreaFrame].origin
                            let x = location.x - origin.x
                            if let date: Date = proxy.value(atX: x) {
                                let cal = Calendar.current
                                selectedMonthlyId = data
                                    .min(by: {
                                        abs(cal.dateComponents([.day], from: $0.date, to: date).day ?? .max)
                                        < abs(cal.dateComponents([.day], from: $1.date, to: date).day ?? .max)
                                    })?.id
                            }
                        case .ended:
                            selectedMonthlyId = nil
                        }
                    }
            }
        }
        .frame(height: 50)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
    }

    // MARK: - Trend

    /// Precomputed trend data — avoids duplicate Date()/Calendar/throttleCount calls.
    private struct TrendData {
        let change: ChangeInfo?
        let stat: String?
        let throttleCount: Int
        let peak: String?
        let throttleDays: Int
    }

    private func trendSummary(_ snapshot: UsageSnapshot) -> some View {
        let data = computeTrendData(snapshot)
        return VStack(spacing: 4) {
            trendRowTop(change: data.change, stat: data.stat)
            trendRowBottom(throttleCount: data.throttleCount, peak: data.peak)
        }
        .padding(.top, 4)
        .copyable(trendCopyText(data))
    }

    /// Compute all trend values once per render — shared by display and copy text.
    private func computeTrendData(_ snapshot: UsageSnapshot) -> TrendData {
        let cal = Calendar.current
        let now = Date()

        switch mode {
        case .hourly:
            return TrendData(
                change: changeVsYesterday(snapshot, cal: cal, now: now),
                stat: "\(snapshot.todayMessages) msgs today",
                throttleCount: UsageViewModel.throttleCount(days: 1),
                peak: snapshot.peakHour.map { "Peak: \(Self.formatHourLabel($0)):00" },
                throttleDays: 1
            )
        case .daily:
            return TrendData(
                change: changeVsLastWeek(snapshot, cal: cal, now: now),
                stat: snapshot.dailyAverage > 0 ? "\(snapshot.dailyAverage) avg/day" : nil,
                throttleCount: UsageViewModel.throttleCount(days: 7),
                peak: snapshot.busiestDayOfWeek.map { "Peak: \($0.name)s" },
                throttleDays: 7
            )
        case .monthly:
            let totals = cachedMonthTotals
            let nowComps = cal.dateComponents([.year, .month], from: now)
            let thisMonthKey = nowComps.year.flatMap { y in nowComps.month.map { m in String(format: "%04d-%02d", y, m) } }
            let lastMonthKey: String? = cal.date(byAdding: .month, value: -1, to: now).flatMap { d in
                let c = cal.dateComponents([.year, .month], from: d)
                return c.year.flatMap { y in c.month.map { m in String(format: "%04d-%02d", y, m) } }
            }
            let thisMonth = thisMonthKey.flatMap { totals[$0] } ?? 0
            let lastMonth = lastMonthKey.flatMap { totals[$0] } ?? 0
            let busiestLabel: String? = {
                guard let peak = totals.max(by: { $0.value < $1.value }),
                      let date = DateFormatters.dateKey.date(from: peak.key + "-01") else { return nil }
                return Self.monthAbbrev(date)
            }()
            return TrendData(
                change: monthChangeInfo(thisMonth: thisMonth, lastMonth: lastMonth, cal: cal, now: now),
                stat: thisMonth > 0 ? "\(Self.compactCount(thisMonth)) this month" : nil,
                throttleCount: UsageViewModel.throttleCount(days: 30),
                peak: busiestLabel.map { "Peak: \($0)" },
                throttleDays: 30
            )
        }
    }

    /// Build copy text from precomputed trend data.
    private func trendCopyText(_ data: TrendData) -> String {
        var lines: [String] = []
        if let change = data.change { lines.append("\(change.symbol) \(change.label)") }
        if let stat = data.stat { lines.append(stat) }
        lines.append("Throttled: \(data.throttleCount > 0 ? "\(data.throttleCount)×" : "0")")
        if let peak = data.peak { lines.append(peak) }
        return lines.joined(separator: " · ")
    }

    // MARK: - Shared trend row builders

    /// Row 1: change indicator (left) + summary stat (right).
    private func trendRowTop(change: ChangeInfo?, stat: String?) -> some View {
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

    /// Row 2: throttle count (left) + peak label (right).
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

    private struct ChangeInfo {
        let symbol: String
        let label: String
        let color: Color
    }

    private func changeVsYesterday(_ snapshot: UsageSnapshot, cal: Calendar = .current, now: Date = .init()) -> ChangeInfo? {
        let yesterdayStr = DateFormatters.dateKey.string(
            from: cal.date(byAdding: .day, value: -1, to: now) ?? now
        )

        guard let yesterday = snapshot.dailyActivity.first(where: { $0.date == yesterdayStr }) else {
            return nil
        }

        let diff = snapshot.todayMessages - yesterday.messageCount

        if diff > 0 {
            return ChangeInfo(symbol: "↑", label: "+\(diff) vs yesterday", color: ThemeColors.trendColor(.up))
        } else if diff < 0 {
            return ChangeInfo(symbol: "↓", label: "\(diff) vs yesterday", color: ThemeColors.trendColor(.down))
        } else {
            return ChangeInfo(symbol: "→", label: "same as yesterday", color: ThemeColors.secondaryLabel)
        }
    }

    /// Compare this week's messages vs the same days last week for a fair comparison.
    /// e.g. on Tuesday, compares Mon–Tue this week vs Mon–Tue last week.
    private func changeVsLastWeek(_ snapshot: UsageSnapshot, cal: Calendar = .current, now: Date = .init()) -> ChangeInfo? {
        let today = cal.startOfDay(for: now)
        let weekday = cal.component(.weekday, from: today)
        // Days since Monday (weekday 2 = Monday in Gregorian), 0 = Monday
        let daysSinceMonday = (weekday + 5) % 7
        guard let thisWeekStart = cal.date(byAdding: .day, value: -daysSinceMonday, to: today),
              let lastWeekStart = cal.date(byAdding: .day, value: -7, to: thisWeekStart),
              // Compare same span: Mon–today this week vs Mon–same day last week
              let lastWeekSameDay = cal.date(byAdding: .day, value: daysSinceMonday, to: lastWeekStart) else {
            return nil
        }

        let thisWeekRange = DateFormatters.dateKey.string(from: thisWeekStart)...DateFormatters.dateKey.string(from: today)
        let lastWeekRange = DateFormatters.dateKey.string(from: lastWeekStart)...DateFormatters.dateKey.string(from: lastWeekSameDay)

        let thisWeekTotal = snapshot.dailyActivity
            .filter { thisWeekRange.contains($0.date) }
            .reduce(0) { $0 + $1.messageCount }
        let lastWeekTotal = snapshot.dailyActivity
            .filter { lastWeekRange.contains($0.date) }
            .reduce(0) { $0 + $1.messageCount }

        guard lastWeekTotal > 0 else { return nil }

        let diff = thisWeekTotal - lastWeekTotal
        let pct = Int(round(Double(diff) / Double(lastWeekTotal) * 100))

        if pct > 10 {
            return ChangeInfo(symbol: "↑", label: "+\(pct)% vs last week", color: ThemeColors.trendColor(.up))
        } else if pct < -10 {
            return ChangeInfo(symbol: "↓", label: "\(pct)% vs last week", color: ThemeColors.trendColor(.down))
        } else {
            return ChangeInfo(symbol: "→", label: "~same as last week", color: ThemeColors.secondaryLabel)
        }
    }

    private func monthChangeInfo(thisMonth: Int, lastMonth: Int, cal: Calendar = .current, now: Date = .init()) -> ChangeInfo? {
        guard lastMonth > 0 else { return nil }

        let dayOfMonth = cal.component(.day, from: now)
        guard dayOfMonth >= 4,
              let daysInMonth = cal.range(of: .day, in: .month, for: now)?.count else { return nil }
        let projected = thisMonth * daysInMonth / dayOfMonth
        let diff = projected - lastMonth
        let pct = Int(round(Double(diff) / Double(lastMonth) * 100))

        if pct > 10 {
            return ChangeInfo(symbol: "↑", label: "+\(pct)% vs last month", color: ThemeColors.trendColor(.up))
        } else if pct < -10 {
            return ChangeInfo(symbol: "↓", label: "\(pct)% vs last month", color: ThemeColors.trendColor(.down))
        } else {
            return ChangeInfo(symbol: "→", label: "~same as last month", color: ThemeColors.secondaryLabel)
        }
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

    // MARK: - Formatters

    static func dayShortLabel(_ date: Date) -> String {
        DateFormatters.shortDay.string(from: date)
    }

    static func monthAbbrev(_ date: Date) -> String {
        DateFormatters.shortMonth.string(from: date)
    }

    /// Compact integer counts for chart axes (e.g. 1500 → "2K").
    /// Differs from TokenFormatter which formats fractional token values (e.g. 1500 → "1.5K").
    private static func compactCount(_ value: Int) -> String {
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

    private static func formatHourLabel(_ hour: Int) -> String {
        guard hour >= 0 && hour < 24 else { return String(format: "%02d", hour) }
        return hourLabels[hour]
    }
}
