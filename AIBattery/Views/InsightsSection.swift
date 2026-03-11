import SwiftUI

struct InsightsSection: View {
    let snapshot: UsageSnapshot
    @AppStorage(UserDefaultsKeys.insightsCollapsed) private var collapsed: Bool = false

    /// Fixed width for left-side labels so values align in a clean column.
    private let labelWidth: CGFloat = 55

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack {
                CollapsibleSectionHeader(
                    title: "Insights",
                    collapsed: $collapsed,
                    tooltip: "Session and message statistics"
                )
                Spacer()
                if collapsed {
                    Text(collapsedSummary)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(ThemeColors.secondaryLabel)
                        .lineLimit(1)
                }
            }

            if !collapsed {
                // Today
                insightRow(
                    label: "Today",
                    value: todayStats,
                    tooltip: "Activity since midnight"
                )
                .accessibilityLabel("Today: \(snapshot.todayMessages) messages, \(snapshot.todaySessions) sessions")

                // Tool calls (today's detail)
                if snapshot.todayToolCalls > 0 {
                    insightRow(
                        label: "Tools",
                        value: "\(snapshot.todayToolCalls) calls today",
                        tooltip: "Tool invocations today"
                    )
                }

                // All time
                insightRow(
                    label: "All Time",
                    value: allTimeStats,
                    tooltip: "Cumulative activity across all sessions"
                )
                .accessibilityLabel("All time: \(snapshot.totalMessages) messages, \(snapshot.totalSessions) sessions")

                // Longest session (all-time detail)
                if let duration = snapshot.longestSessionDuration, snapshot.longestSessionMessages > 0 {
                    let longestText = "\(duration) \u{00B7} \(snapshot.longestSessionMessages) msgs"
                    insightRow(
                        label: "Longest",
                        value: longestText,
                        tooltip: "Longest single session by duration"
                    )
                }

                // Date range (metadata)
                if let range = dataDateRange {
                    insightRow(
                        label: "Period",
                        value: range,
                        tooltip: "Date range of tracked data",
                        valueColor: ThemeColors.secondaryLabel
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Row

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
                .frame(width: labelWidth, alignment: .leading)
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

    // MARK: - Computed

    private var collapsedSummary: String {
        "\(snapshot.todayMessages) msgs \u{00B7} \(snapshot.todaySessions) sessions"
    }

    private var todayStats: String {
        "\(snapshot.todayMessages) msgs \u{00B7} \(snapshot.todaySessions) sessions"
    }

    private var allTimeStats: String {
        "\(snapshot.totalMessages) msgs \u{00B7} \(snapshot.totalSessions) sessions"
    }

    /// Date range the data covers, e.g. "Nov 6 – Mar 10, 2026".
    private var dataDateRange: String? {
        guard let start = snapshot.firstSessionDate,
              let lastDay = snapshot.dailyActivity.last?.date,
              let end = DateFormatters.dateKey.date(from: lastDay) else { return nil }
        return DateFormatters.formatDateRange(from: start, to: end)
    }
}
