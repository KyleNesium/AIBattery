import SwiftUI

struct InsightsSection: View {
    let snapshot: UsageSnapshot

    /// Fixed width for left-side labels so values align in a clean column.
    private let labelWidth: CGFloat = 55

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Today's activity
            HStack {
                Text("Today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: labelWidth, alignment: .leading)
                    .help("Activity since midnight")
                Spacer()
                Text(todayStats)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .copyable(todayStats)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Today: \(snapshot.todayMessages) messages, \(snapshot.todaySessions) sessions\(snapshot.todayToolCalls > 0 ? ", \(snapshot.todayToolCalls) tool calls" : "")")

            // All time totals
            HStack {
                Text("All Time")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: labelWidth, alignment: .leading)
                    .help("Cumulative activity across all sessions")
                Spacer()
                Text(allTimeStats)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .copyable(allTimeStats)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("All time: \(snapshot.totalMessages) messages, \(snapshot.totalSessions) sessions")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Computed strings

    private var todayStats: String {
        if snapshot.todayToolCalls > 0 {
            return "\(snapshot.todayMessages) msgs \u{00B7} \(snapshot.todaySessions) sess \u{00B7} \(snapshot.todayToolCalls) tools"
        }
        return "\(snapshot.todayMessages) msgs \u{00B7} \(snapshot.todaySessions) sessions"
    }

    private var allTimeStats: String {
        "\(snapshot.totalMessages) msgs \u{00B7} \(snapshot.totalSessions) sessions"
    }
}
