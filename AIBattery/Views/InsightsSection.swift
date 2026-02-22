import SwiftUI

struct InsightsSection: View {
    let snapshot: UsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Today's activity
            HStack {
                Text("Today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                let todayStats = "\(snapshot.todayMessages) msgs \u{00B7} \(snapshot.todaySessions) sessions \u{00B7} \(snapshot.todayToolCalls) tools"
                Text(todayStats)
                    .font(.system(.caption, design: .monospaced))
                    .copyable(todayStats)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Today: \(snapshot.todayMessages) messages, \(snapshot.todaySessions) sessions, \(snapshot.todayToolCalls) tool calls")

            // Totals
            HStack {
                Text("All Time")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                let allTimeStats = "\(snapshot.totalMessages) msgs \u{00B7} \(snapshot.totalSessions) sessions"
                Text(allTimeStats)
                    .font(.system(.caption, design: .monospaced))
                    .copyable(allTimeStats)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("All time: \(snapshot.totalMessages) messages, \(snapshot.totalSessions) sessions")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
