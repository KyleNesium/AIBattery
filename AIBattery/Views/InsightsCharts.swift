import SwiftUI
import Charts

// MARK: - Chart styling and chart views

extension InsightsView {

    // MARK: - Shared chart styling

    /// Shared area gradient used by all three chart modes (daily/hourly/monthly).
    static let areaGradient: LinearGradient = .linearGradient(
        colors: [ThemeColors.chartAccent.opacity(0.3), ThemeColors.chartAccent.opacity(0.1)],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Shared line style used by all chart modes.
    static let chartLineStyle = StrokeStyle(lineWidth: 1.5)

    /// Standard Y-axis for all chart modes: trailing position, 3 ticks, compact count labels.
    var sharedYAxis: some AxisContent {
        AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
            AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(ThemeColors.tertiaryLabel)
            AxisValueLabel {
                if let v = value.as(Int.self) {
                    Text(Self.compactCount(v))
                        .font(Typography.decorativeIcon)
                        .foregroundStyle(ThemeColors.tertiaryLabel)
                }
            }
        }
    }

    // MARK: - Daily Chart (7D)

    var dailyChart: some View {
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
                .foregroundStyle(Self.areaGradient)
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Messages", point.count)
                )
                .foregroundStyle(ThemeColors.chartAccent)
                .lineStyle(Self.chartLineStyle)
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
            }
        }
        .chartXAxis {
            AxisMarks(values: dates) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(Self.dayShortLabel(date))
                            .font(Typography.monoTiny)
                    }
                }
            }
        }
        .chartYAxis { sharedYAxis }
        .chartPlotStyle { plot in plot.background(.clear) }
        .chartOverlay { proxy in
            chartHoverOverlay(proxy: proxy, tooltipText: hoverTooltipText) { x in
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
        .frame(height: Layout.chartHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
    }

    // MARK: - Hourly Chart (24H)

    var hourlyChart: some View {
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
                .foregroundStyle(Self.areaGradient)
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Hour", point.id),
                    y: .value("Messages", point.count)
                )
                .foregroundStyle(ThemeColors.chartAccent)
                .lineStyle(Self.chartLineStyle)
                .interpolationMethod(.catmullRom)
            }

            if let selectedOffset = selectedHourlyOffset,
               let point = data.first(where: { $0.id == selectedOffset }) {
                RuleMark(x: .value("Selected", point.id))
                    .foregroundStyle(ThemeColors.tertiaryLabel)
                    .lineStyle(Self.selectionRuleStyle)
            }
        }
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18]) { value in
                AxisValueLabel {
                    if let offset = value.as(Int.self), offset >= 0, offset < data.count {
                        Text(Self.formatHourLabelFull(data[offset].hour))
                            .font(Typography.decorativeIcon)
                    }
                }
            }
        }
        .chartXScale(domain: 0...23)
        .chartYAxis { sharedYAxis }
        .chartPlotStyle { plot in plot.background(.clear) }
        .chartOverlay { proxy in
            chartHoverOverlay(proxy: proxy, tooltipText: hoverTooltipText) { x in
                guard let value: Double = proxy.value(atX: x) else { return }
                selectedHourlyOffset = max(0, min(23, Int(value.rounded())))
            } onEnd: {
                selectedHourlyOffset = nil
            }
        }
        .frame(height: Layout.chartHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
    }

    // MARK: - Monthly Chart (12M)

    var monthlyChart: some View {
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
                .foregroundStyle(Self.areaGradient)
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Month", point.date, unit: .month),
                    y: .value("Messages", point.count)
                )
                .foregroundStyle(ThemeColors.chartAccent)
                .lineStyle(Self.chartLineStyle)
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
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month, count: 3)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(Self.monthAbbrev(date))
                            .font(Typography.monoTiny)
                    }
                }
            }
        }
        .chartYAxis { sharedYAxis }
        .chartPlotStyle { plot in plot.background(.clear) }
        .chartOverlay { proxy in
            chartHoverOverlay(proxy: proxy, tooltipText: hoverTooltipText) { x in
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
        .frame(height: Layout.chartHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
    }
}
