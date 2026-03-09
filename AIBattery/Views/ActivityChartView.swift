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

    // MARK: - Data transforms (delegated to ActivityChartData for testability)

    private var dailyData: [ActivityChartData.DailyPoint] {
        ActivityChartData.dailyData(from: dailyActivity)
    }

    private var hourlyData: [ActivityChartData.HourlyPoint] {
        ActivityChartData.hourlyData(from: todayHourCounts)
    }

    private var monthlyData: [ActivityChartData.MonthlyPoint] {
        ActivityChartData.monthlyData(from: dailyActivity)
    }

    /// Check source data directly — avoids recomputing dailyData/monthlyData just for an emptiness check.
    private var isEmpty: Bool {
        switch mode {
        case .daily: return dailyActivity.allSatisfy { $0.messageCount == 0 }
        case .hourly: return todayHourCounts.values.allSatisfy { $0 == 0 }
        case .monthly: return dailyActivity.allSatisfy { $0.messageCount == 0 }
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with toggle
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { collapsed.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .rotationEffect(.degrees(collapsed ? 0 : 90))
                            .foregroundStyle(ThemeColors.tertiaryLabel)
                        Text("Activity")
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(collapsed ? "Double-tap to expand" : "Double-tap to collapse")
                .help("Message activity over time")
                if collapsed, let snapshot, let change = changeVsYesterday(snapshot) {
                    Text(change.symbol)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(change.color)
                    Text(change.label)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(change.color)
                }
                Spacer()
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
                    Text("No activity data")
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
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Daily Chart (7D)

    private var dailyChart: some View {
        let data = dailyData
        let dates = data.map(\.date)
        let total = data.reduce(0) { $0 + $1.count }
        let peak = data.max(by: { $0.count < $1.count })
        let a11yLabel: String = {
            if let peak, peak.count > 0 {
                return "7-day activity chart. \(total) messages this week. Peak: \(peak.count) on \(Self.dayShortLabel(peak.date))"
            }
            return "7-day activity chart. \(total) messages this week"
        }()

        return Chart(data) { point in
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
        .frame(height: 50)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
    }

    // MARK: - Hourly Chart (12H)

    private var hourlyChart: some View {
        let data = hourlyData
        let total = data.reduce(0) { $0 + $1.count }
        let peak = data.max(by: { $0.count < $1.count })
        let a11yLabel: String = {
            if let peak, peak.count > 0 {
                return "12-hour activity chart. \(total) messages in trailing window. Peak hour: \(Self.formatHourLabel(peak.hour)) with \(peak.count) messages"
            }
            return "12-hour activity chart. \(total) messages in trailing window"
        }()

        return Chart(data) { point in
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
        .frame(height: 50)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
    }

    // MARK: - Monthly Chart (12M)

    private var monthlyChart: some View {
        let data = monthlyData
        let dates = data.map(\.date)
        // Use actual (non-projected) total for accessibility — projected data is only for visual comparison
        let actualTotal = dailyActivity.reduce(0) { $0 + $1.messageCount }
        let a11yLabel = "12-month activity chart. \(actualTotal) messages total"

        return Chart(data) { point in
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
        .frame(height: 50)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
    }

    // MARK: - Trend

    private func trendSummary(_ snapshot: UsageSnapshot) -> some View {
        VStack(spacing: 4) {
            switch mode {
            case .hourly:
                trendRow12H(snapshot)
            case .daily:
                trendRow7D(snapshot)
            case .monthly:
                trendRow12M(snapshot)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - 12H trend

    private func trendRow12H(_ snapshot: UsageSnapshot) -> some View {
        Group {
            HStack(spacing: 6) {
                if let change = changeVsYesterday(snapshot) {
                    Text(change.symbol)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(change.color)
                    Text(change.label)
                        .font(.system(.caption, design: .monospaced, weight: .medium))
                        .foregroundStyle(change.color)
                }
                Spacer()
                Text("\(snapshot.todayMessages) msgs today")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(ThemeColors.secondaryLabel)
            }
            HStack(spacing: 6) {
                throttleLabel(days: 1, period: "today")
                Spacer()
                if let peak = snapshot.peakHour {
                    Text("Peak at \(Self.formatHourLabel(peak)):00")
                        .font(.caption)
                        .foregroundStyle(ThemeColors.tertiaryLabel)
                }
            }
        }
    }

    // MARK: - 7D trend

    private func trendRow7D(_ snapshot: UsageSnapshot) -> some View {
        Group {
            HStack(spacing: 6) {
                Text(snapshot.trendDirection.symbol)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ThemeColors.trendColor(snapshot.trendDirection))
                if let change = changeVsYesterday(snapshot) {
                    Text(change.label)
                        .font(.system(.caption, design: .monospaced, weight: .medium))
                        .foregroundStyle(change.color)
                }
                Spacer()
                if snapshot.dailyAverage > 0 {
                    Text("\(snapshot.dailyAverage) avg/day")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(ThemeColors.secondaryLabel)
                }
            }
            HStack(spacing: 6) {
                throttleLabel(days: 7, period: "this week")
                Spacer()
                if let busiest = snapshot.busiestDayOfWeek {
                    Text("Peak on \(busiest.name)s")
                        .font(.caption)
                        .foregroundStyle(ThemeColors.tertiaryLabel)
                }
            }
        }
    }

    // MARK: - 12M trend

    private func trendRow12M(_ snapshot: UsageSnapshot) -> some View {
        let totals = monthTotals
        let cal = Calendar.current
        let now = Date()
        let nowComps = cal.dateComponents([.year, .month], from: now)
        let thisMonthKey = nowComps.year.flatMap { y in nowComps.month.map { m in String(format: "%04d-%02d", y, m) } }
        let lastMonthKey: String? = cal.date(byAdding: .month, value: -1, to: now).flatMap { d in
            let c = cal.dateComponents([.year, .month], from: d)
            return c.year.flatMap { y in c.month.map { m in String(format: "%04d-%02d", y, m) } }
        }
        let thisMonth = thisMonthKey.flatMap { totals[$0] } ?? 0
        let lastMonth = lastMonthKey.flatMap { totals[$0] } ?? 0
        let change = monthChangeInfo(thisMonth: thisMonth, lastMonth: lastMonth)
        let busiestLabel: String? = {
            guard let peak = totals.max(by: { $0.value < $1.value }),
                  let date = DateFormatters.dateKey.date(from: peak.key + "-01") else { return nil }
            return Self.monthAbbrev(date)
        }()

        return Group {
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
                if thisMonth > 0 {
                    Text("\(Self.compactCount(thisMonth)) this month")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(ThemeColors.secondaryLabel)
                }
            }
            HStack(spacing: 6) {
                throttleLabel(days: 30, period: "this month")
                Spacer()
                if let busiestLabel {
                    Text("Peak in \(busiestLabel)")
                        .font(.caption)
                        .foregroundStyle(ThemeColors.tertiaryLabel)
                }
            }
        }
    }

    // MARK: - Shared helpers

    @ViewBuilder
    private func throttleLabel(days: Int, period: String) -> some View {
        let count = UsageViewModel.throttleCount(days: days)
        if count > 0 {
            Text("\(count)× throttled \(period)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(ThemeColors.caution)
        } else {
            Text("0 throttles \(period)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(ThemeColors.secondaryLabel)
        }
    }

    private struct ChangeInfo {
        let symbol: String
        let label: String
        let color: Color
    }

    private func changeVsYesterday(_ snapshot: UsageSnapshot) -> ChangeInfo? {
        let yesterdayStr = DateFormatters.dateKey.string(
            from: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
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
            return ChangeInfo(symbol: "→", label: "same as yesterday", color: .secondary)
        }
    }

    /// Single-pass aggregation of daily activity into month-keyed totals (e.g. "2026-03" → 142).
    /// Shared by `monthlyData` (chart rendering) and `trendRow12M` (trend summary).
    private var monthTotals: [String: Int] {
        ActivityChartData.monthTotals(from: dailyActivity)
    }

    private func monthChangeInfo(thisMonth: Int, lastMonth: Int) -> ChangeInfo? {
        guard lastMonth > 0 else { return nil }

        let cal = Calendar.current
        let now = Date()
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
            return ChangeInfo(symbol: "→", label: "~same as last month", color: .secondary)
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
