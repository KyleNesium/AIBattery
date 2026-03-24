import SwiftUI
import Charts

// MARK: - Insight rows, hover helpers, and static formatters

extension InsightsView {

    // MARK: - Insight rows (merged from former Insights section)

    static let insightLabelWidth: CGFloat = 55

    @ViewBuilder
    func insightRows(_ snapshot: UsageSnapshot) -> some View {
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

    func insightRow(
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
            return "\(Self.monthAbbrev(point.date)) — \(Self.compactCount(point.count)) msgs"
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

    /// Testable isEmpty logic for the hourly chart mode.
    /// Returns false when dailyActivity has records for today (loading signal),
    /// even if todayHourCounts is empty or all-zero (JSONL scan still in progress).
    static func isHourlyEmpty(todayHourCounts: [String: Int], dailyActivity: [DailyActivity]) -> Bool {
        let todayKey = DateFormatters.dateKey.string(from: Date())
        if dailyActivity.contains(where: { $0.date == todayKey && $0.messageCount > 0 }) {
            return false
        }
        return todayHourCounts.values.allSatisfy { $0 == 0 }
    }

    /// Full HH:00 format for chart x-axis labels (e.g. "06:00", "18:00").
    /// Distinct from formatHourLabel which returns "HH" only (used in tooltips/trend with manual :00 suffix).
    static func formatHourLabelFull(_ hour: Int) -> String {
        return String(format: "%02d:00", max(0, min(23, hour)))
    }

    /// Returns the subset of dates to label on the 12M x-axis:
    /// quarterly anchor months (Jan=1, Apr=4, Jul=7, Oct=10) plus the current month.
    /// `allDates` must be start-of-month Dates ordered chronologically.
    /// `now` is injectable for testing.
    static func quarterlyLabelDates(from allDates: [Date], now: Date = Date()) -> [Date] {
        let cal = Calendar.current
        let currentMonth = cal.component(.month, from: now)
        let currentYear = cal.component(.year, from: now)
        return allDates.filter { date in
            let month = cal.component(.month, from: date)
            let year = cal.component(.year, from: date)
            let isQuarterly = (month % 3 == 1)   // Jan(1), Apr(4), Jul(7), Oct(10)
            let isCurrent = (month == currentMonth && year == currentYear)
            return isQuarterly || isCurrent
        }
    }
}
