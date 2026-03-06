import SwiftUI
import Charts

// MARK: - Chart Mode

enum ActivityChartMode: String, CaseIterable {
    case hourly = "12H"
    case daily = "7D"
    case monthly = "12M"
}

// MARK: - Data Points

private struct DailyPoint: Identifiable {
    let id: String
    let date: Date
    let count: Int
}

private struct HourlyPoint: Identifiable {
    let id: Int
    let hour: Int
    let count: Int
}

private struct MonthlyPoint: Identifiable {
    let id: String
    let date: Date
    let count: Int
}

// MARK: - View

struct ActivityChartView: View {
    let dailyActivity: [DailyActivity]
    let todayHourCounts: [String: Int]
    var snapshot: UsageSnapshot?

    @AppStorage(UserDefaultsKeys.chartMode) private var modeRaw: String = ActivityChartMode.hourly.rawValue

    private var mode: ActivityChartMode {
        ActivityChartMode(rawValue: modeRaw) ?? .hourly
    }

    // MARK: - Data transforms

    private var dailyData: [DailyPoint] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // Build lookup from existing data
        var lookup: [String: Int] = [:]
        for day in dailyActivity {
            lookup[day.date] = day.messageCount
        }

        // Generate all 7 days (6 days ago through today)
        return (0..<7).compactMap { offset in
            guard let date = cal.date(byAdding: .day, value: -(6 - offset), to: today) else { return nil }
            let key = DateFormatters.dateKey.string(from: date)
            return DailyPoint(id: key, date: date, count: lookup[key] ?? 0)
        }
    }

    private var hourlyData: [HourlyPoint] {
        let currentHour = Calendar.current.component(.hour, from: Date())
        return (0..<12).map { offset in
            let hour = (currentHour - 11 + offset + 24) % 24
            return HourlyPoint(id: offset, hour: hour, count: todayHourCounts[String(hour)] ?? 0)
        }
    }

    private var monthlyData: [MonthlyPoint] {
        let cal = Calendar.current
        let now = Date()

        // Build lookup: aggregate daily data into month buckets
        var lookup: [String: Int] = [:]
        for day in dailyActivity {
            guard let date = day.parsedDate else { continue }
            let comps = cal.dateComponents([.year, .month], from: date)
            guard let year = comps.year, let month = comps.month else { continue }
            let key = String(format: "%04d-%02d", year, month)
            lookup[key, default: 0] += day.messageCount
        }

        // Generate all 12 months (11 months ago through this month)
        let nowComps = cal.dateComponents([.year, .month], from: now)
        guard let thisMonth = cal.date(from: nowComps) else { return [] }
        guard let nowYear = nowComps.year, let nowMonth = nowComps.month else { return [] }
        let thisMonthKey = String(format: "%04d-%02d", nowYear, nowMonth)

        return (0..<12).compactMap { offset in
            guard let date = cal.date(byAdding: .month, value: -(11 - offset), to: thisMonth) else { return nil }
            let comps = cal.dateComponents([.year, .month], from: date)
            guard let y = comps.year, let m = comps.month else { return nil }
            let key = String(format: "%04d-%02d", y, m)
            let total = lookup[key] ?? 0

            // Project current month to full-month pace so it's comparable.
            // Skip projection in the first 3 days — too few data points to extrapolate.
            let count: Int
            if key == thisMonthKey, total > 0,
               let daysInMonth = cal.range(of: .day, in: .month, for: now)?.count {
                let dayOfMonth = cal.component(.day, from: now)
                count = dayOfMonth >= 4 ? total * daysInMonth / dayOfMonth : total
            } else {
                count = total
            }

            return MonthlyPoint(id: key, date: date, count: count)
        }
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
                Text("Activity")
                    .font(.subheadline.bold())
                Spacer()
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

            if isEmpty {
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
            if let snapshot {
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
        .chartYAxis {
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
                    if let offset = value.as(Int.self), offset < data.count {
                        Text(Self.formatHourLabel(data[offset].hour))
                            .font(.system(size: 8))
                    }
                }
            }
        }
        .chartXScale(domain: 0...11)
        .chartYAxis {
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
        .chartYAxis {
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
        let change = changeVsLastMonth(snapshot)
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
                let thisMonth = monthTotal(snapshot, offset: 0)
                if thisMonth > 0 {
                    Text("\(Self.compactCount(thisMonth)) this month")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(ThemeColors.secondaryLabel)
                }
            }
            HStack(spacing: 6) {
                throttleLabel(days: 30, period: "this month")
                Spacer()
                let busiest = busiestMonth(snapshot)
                if let busiest {
                    Text("Peak in \(busiest)")
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

    private func changeVsLastMonth(_ snapshot: UsageSnapshot) -> ChangeInfo? {
        let thisMonth = monthTotal(snapshot, offset: 0)
        let lastMonth = monthTotal(snapshot, offset: -1)
        guard lastMonth > 0 else { return nil }

        // Project current month to compare fairly
        let cal = Calendar.current
        let now = Date()
        let dayOfMonth = cal.component(.day, from: now)
        guard dayOfMonth >= 4,
              let daysInMonth = cal.range(of: .day, in: .month, for: now)?.count else { return nil }
        let projected = thisMonth * daysInMonth / dayOfMonth
        let diff = projected - lastMonth
        let pct = lastMonth > 0 ? Int(round(Double(diff) / Double(lastMonth) * 100)) : 0

        if pct > 10 {
            return ChangeInfo(symbol: "↑", label: "+\(pct)% vs last month", color: ThemeColors.trendColor(.up))
        } else if pct < -10 {
            return ChangeInfo(symbol: "↓", label: "\(pct)% vs last month", color: ThemeColors.trendColor(.down))
        } else {
            return ChangeInfo(symbol: "→", label: "~same as last month", color: .secondary)
        }
    }

    private func monthTotal(_ snapshot: UsageSnapshot, offset: Int) -> Int {
        let cal = Calendar.current
        let now = Date()
        guard let target = cal.date(byAdding: .month, value: offset, to: now) else { return 0 }
        let comps = cal.dateComponents([.year, .month], from: target)
        guard let y = comps.year, let m = comps.month else { return 0 }
        let prefix = String(format: "%04d-%02d", y, m)
        return snapshot.dailyActivity
            .filter { $0.date.hasPrefix(prefix) }
            .reduce(0) { $0 + $1.messageCount }
    }

    private func busiestMonth(_ snapshot: UsageSnapshot) -> String? {
        let cal = Calendar.current
        var monthTotals: [String: Int] = [:]
        for day in snapshot.dailyActivity {
            guard let date = day.parsedDate else { continue }
            let comps = cal.dateComponents([.year, .month], from: date)
            guard let y = comps.year, let m = comps.month else { continue }
            let key = String(format: "%04d-%02d", y, m)
            monthTotals[key, default: 0] += day.messageCount
        }
        guard let peak = monthTotals.max(by: { $0.value < $1.value }),
              let date = DateFormatters.dateKey.date(from: peak.key + "-01") else { return nil }
        return Self.monthAbbrev(date)
    }

    // MARK: - Formatters

    static func dayShortLabel(_ date: Date) -> String {
        DateFormatters.shortDay.string(from: date)
    }

    static func monthAbbrev(_ date: Date) -> String {
        DateFormatters.shortMonth.string(from: date)
    }

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
