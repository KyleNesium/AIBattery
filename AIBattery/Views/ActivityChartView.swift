import SwiftUI
import Charts

// MARK: - Chart Mode

enum ActivityChartMode: String, CaseIterable {
    case hourly = "24H"
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
    let hourCounts: [String: Int]

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
            let key = Self.dateKeyFormatter.string(from: date)
            return DailyPoint(id: key, date: date, count: lookup[key] ?? 0)
        }
    }

    private var hourlyData: [HourlyPoint] {
        (0..<24).map { hour in
            HourlyPoint(id: hour, hour: hour, count: hourCounts[String(hour)] ?? 0)
        }
    }

    private var monthlyData: [MonthlyPoint] {
        let cal = Calendar.current

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
        let nowComps = cal.dateComponents([.year, .month], from: Date())
        guard let thisMonth = cal.date(from: nowComps) else { return [] }

        return (0..<12).compactMap { offset in
            guard let date = cal.date(byAdding: .month, value: -(11 - offset), to: thisMonth) else { return nil }
            let comps = cal.dateComponents([.year, .month], from: date)
            guard let y = comps.year, let m = comps.month else { return nil }
            let key = String(format: "%04d-%02d", y, m)
            return MonthlyPoint(id: key, date: date, count: lookup[key] ?? 0)
        }
    }

    private var isEmpty: Bool {
        switch mode {
        case .daily: return dailyData.allSatisfy { $0.count == 0 }
        case .hourly: return hourCounts.values.allSatisfy { $0 == 0 }
        case .monthly: return monthlyData.allSatisfy { $0.count == 0 }
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header with toggle
            HStack {
                Text("Activity")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
                .accessibilityHint("Switch between 24 hour, 7 day, and 12 month views")
                .help("Switch activity chart time range")
            }

            if isEmpty {
                Text("No activity data")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(height: 40)
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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Daily Chart (7D)

    private var dailyChart: some View {
        let dates = dailyData.map(\.date)
        return Chart(dailyData) { point in
            AreaMark(
                x: .value("Day", point.date, unit: .day),
                y: .value("Messages", point.count)
            )
            .foregroundStyle(
                .linearGradient(
                    colors: [.orange.opacity(0.3), .orange.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("Day", point.date, unit: .day),
                y: .value("Messages", point.count)
            )
            .foregroundStyle(.orange)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
            .interpolationMethod(.catmullRom)

            PointMark(
                x: .value("Day", point.date, unit: .day),
                y: .value("Messages", point.count)
            )
            .foregroundStyle(.orange)
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
        .chartYAxis(.hidden)
        .chartPlotStyle { plot in plot.background(.clear) }
        .frame(height: 50)
    }

    // MARK: - Hourly Chart (24H)

    private var hourlyChart: some View {
        Chart(hourlyData) { point in
            AreaMark(
                x: .value("Hour", point.hour),
                y: .value("Messages", point.count)
            )
            .foregroundStyle(
                .linearGradient(
                    colors: [.orange.opacity(0.3), .orange.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("Hour", point.hour),
                y: .value("Messages", point.count)
            )
            .foregroundStyle(.orange)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
            .interpolationMethod(.catmullRom)
        }
        .chartXAxis {
            AxisMarks(values: Array(stride(from: 0, through: 21, by: 3))) { value in
                AxisValueLabel {
                    if let hour = value.as(Int.self) {
                        Text(Self.formatHourLabel(hour))
                            .font(.system(size: 8))
                    }
                }
            }
        }
        .chartXScale(domain: 0...23)
        .chartYAxis(.hidden)
        .chartPlotStyle { plot in plot.background(.clear) }
        .frame(height: 50)
    }

    // MARK: - Monthly Chart (12M)

    private var monthlyChart: some View {
        let dates = monthlyData.map(\.date)
        return Chart(monthlyData) { point in
            AreaMark(
                x: .value("Month", point.date, unit: .month),
                y: .value("Messages", point.count)
            )
            .foregroundStyle(
                .linearGradient(
                    colors: [.orange.opacity(0.3), .orange.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("Month", point.date, unit: .month),
                y: .value("Messages", point.count)
            )
            .foregroundStyle(.orange)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
            .interpolationMethod(.catmullRom)

            PointMark(
                x: .value("Month", point.date, unit: .month),
                y: .value("Messages", point.count)
            )
            .foregroundStyle(.orange)
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
        .chartYAxis(.hidden)
        .chartPlotStyle { plot in plot.background(.clear) }
        .frame(height: 50)
    }

    // MARK: - Formatters

    private static let dateKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let shortDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE" // Mon, Tue, Wed, ...
        return f
    }()

    private static func dayShortLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        return shortDayFormatter.string(from: date)
    }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM" // Jan, Feb, etc.
        return f
    }()

    private static func monthAbbrev(_ date: Date) -> String {
        monthFormatter.string(from: date)
    }

    private static let hourLabels: [String] = (0..<24).map { String(format: "%02d", $0) }

    private static func formatHourLabel(_ hour: Int) -> String {
        guard hour >= 0 && hour < 24 else { return String(format: "%02d", hour) }
        return hourLabels[hour]
    }
}
