import SwiftUI
import Charts

// MARK: - Chart styling and chart views

extension InsightsView {
    // MARK: - Shared chart styling

    /// Shared area gradient used by all three chart modes.
    static let areaGradient: LinearGradient = .linearGradient(
        colors: [ThemeColors.chartAccent.opacity(ThemeColors.chartGradientStartOpacity), ThemeColors.chartAccent.opacity(ThemeColors.chartGradientEndOpacity)],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Shared line style used by all chart modes.
    static let chartLineStyle = StrokeStyle(lineWidth: Layout.borderWidth)

    /// Standard Y-axis for all chart modes: trailing position, 3 ticks, compact count labels.
    var sharedYAxis: some AxisContent {
        AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
            AxisTick(stroke: StrokeStyle(lineWidth: Layout.chartTickWidth))
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
        let data = cachedSevenDay
        let dates = data.map(\.date)
        let total = data.reduce(0) { $0 + $1.count }
        let peak = data.max(by: { $0.count < $1.count })
        let a11yLabel: String = {
            if let peak, peak.count > 0 {
                return "7-day token chart. \(Self.compactCount(total)) tokens this week. Peak: \(Self.compactCount(peak.count)) on \(Self.dayShortLabel(peak.date))"
            }
            return "7-day token chart. \(Self.compactCount(total)) tokens this week"
        }()

        return Chart {
            ForEach(data) { point in
                AreaMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Tokens", point.count)
                )
                .foregroundStyle(Self.areaGradient)
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Tokens", point.count)
                )
                .foregroundStyle(ThemeColors.chartAccent)
                .lineStyle(Self.chartLineStyle)
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Tokens", point.count)
                )
                .foregroundStyle(ThemeColors.chartAccent)
                .symbolSize(Layout.chartSymbolSize)
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
                let ts = date.timeIntervalSinceReferenceDate
                selectedDailyId = data
                    .min(by: {
                        abs($0.date.timeIntervalSinceReferenceDate - ts)
                            < abs($1.date.timeIntervalSinceReferenceDate - ts)
                    })?.id
            } onEnd: {
                selectedDailyId = nil
            }
        }
        .frame(height: Layout.chartHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
    }

    // MARK: - 5-Hour Chart

    var fiveHourChart: some View {
        let data = cachedFiveHour
        let total = data.reduce(0) { $0 + $1.count }
        let a11yLabel = "5-hour token chart. \(Self.compactCount(total)) tokens in trailing 5 hours"

        return Chart {
            ForEach(data) { point in
                AreaMark(
                    x: .value("Bucket", point.id),
                    y: .value("Tokens", point.count)
                )
                .foregroundStyle(Self.areaGradient)
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Bucket", point.id),
                    y: .value("Tokens", point.count)
                )
                .foregroundStyle(ThemeColors.chartAccent)
                .lineStyle(Self.chartLineStyle)
                .interpolationMethod(.catmullRom)
            }

            if let selectedOffset = selectedFiveHourOffset,
               let point = data.first(where: { $0.id == selectedOffset }) {
                RuleMark(x: .value("Selected", point.id))
                    .foregroundStyle(ThemeColors.tertiaryLabel)
                    .lineStyle(Self.selectionRuleStyle)
            }
        }
        .chartXAxis {
            // Show 4 evenly-spaced clock times: -5h, -3h45m, -2h30m, -1h15m, now
            AxisMarks(values: [0, 5, 10, 15, 19]) { value in
                AxisValueLabel {
                    if let offset = value.as(Int.self) {
                        Text(Self.fiveHourAxisLabel(offset: offset))
                            .font(Typography.decorativeIcon)
                    }
                }
            }
        }
        .chartXScale(domain: 0...19)
        .chartYAxis { sharedYAxis }
        .chartPlotStyle { plot in plot.background(.clear) }
        .chartOverlay { proxy in
            chartHoverOverlay(proxy: proxy, tooltipText: hoverTooltipText) { x in
                guard let value: Double = proxy.value(atX: x) else { return }
                selectedFiveHourOffset = max(0, min(19, Int(value.rounded())))
            } onEnd: {
                selectedFiveHourOffset = nil
            }
        }
        .frame(height: Layout.chartHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
    }

    /// Clock-time label for a 5-hour chart bucket offset.
    /// offset 0 = 5h ago, offset 19 = now. Shows "HH:MM" format.
    static func fiveHourAxisLabel(offset: Int, now: Date = .now) -> String {
        if offset == 19 { return "Now" }
        let minutesAgo = Double(19 - offset) * 15
        let date = now.addingTimeInterval(-minutesAgo * 60)
        let hour = Calendar.current.component(.hour, from: date)
        let minute = Calendar.current.component(.minute, from: date)
        return String(format: "%02d:%02d", hour, minute)
    }

    // MARK: - Monthly Chart (12M)

    @ViewBuilder
    var monthlyChart: some View {
        let data = cachedMonthly
        if data.isEmpty {
            VStack(spacing: Spacing.inner) {
                Image(systemName: "calendar.badge.clock")
                    .font(Typography.stateIcon)
                    .foregroundStyle(ThemeColors.tertiaryLabel)
                Text("Need 30+ days of data for monthly view")
                    .font(Typography.tinyLabel)
                    .foregroundStyle(ThemeColors.tertiaryLabel)
            }
            .frame(height: Layout.chartHeight)
            .frame(maxWidth: .infinity)
        } else {
            monthlyChartContent(data: data)
        }
    }

    /// Extracted chart body — avoids Swift Charts crash on empty ForEach with AxisMarks.
    private func monthlyChartContent(data: [ActivityChartData.MonthlyPoint]) -> some View {
        let total = data.reduce(0) { $0 + $1.count }
        let a11yLabel = "12-month token chart. \(Self.compactCount(total)) tokens total"

        return Chart {
            ForEach(data) { point in
                AreaMark(
                    x: .value("Month", point.date, unit: .month),
                    y: .value("Tokens", point.count)
                )
                .foregroundStyle(Self.areaGradient)
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Month", point.date, unit: .month),
                    y: .value("Tokens", point.count)
                )
                .foregroundStyle(ThemeColors.chartAccent)
                .lineStyle(Self.chartLineStyle)
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Month", point.date, unit: .month),
                    y: .value("Tokens", point.count)
                )
                .foregroundStyle(ThemeColors.chartAccent)
                .symbolSize(Layout.chartSymbolSize)
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
                let ts = date.timeIntervalSinceReferenceDate
                selectedMonthlyId = data
                    .min(by: {
                        abs($0.date.timeIntervalSinceReferenceDate - ts)
                            < abs($1.date.timeIntervalSinceReferenceDate - ts)
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
