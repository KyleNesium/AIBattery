import SwiftUI

struct InsightsSection: View {
    let snapshot: UsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Today's activity with trend
            HStack {
                HStack(spacing: 4) {
                    Text("Today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(snapshot.trendDirection.symbol)
                        .font(.caption)
                        .foregroundStyle(trendColor)
                }
                Spacer()
                let projected = snapshot.projectedTodayTotal
                let todayStats = "\(snapshot.todayMessages) msgs \u{00B7} \(snapshot.todaySessions) sessions \u{00B7} \(snapshot.todayToolCalls) tools"
                HStack(spacing: 4) {
                    Text(todayStats)
                        .font(.system(.caption, design: .monospaced))
                        .copyable(todayStats)
                    if projected > snapshot.todayMessages {
                        Text("(\u{2192}\(projected))")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Today: \(snapshot.todayMessages) messages, \(snapshot.todaySessions) sessions, \(snapshot.todayToolCalls) tool calls")

            // Totals + busiest day
            HStack {
                Text("All Time")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                let allTimeStats = "\(snapshot.totalMessages) msgs \u{00B7} \(snapshot.totalSessions) sessions"
                HStack(spacing: 4) {
                    Text(allTimeStats)
                        .font(.system(.caption, design: .monospaced))
                        .copyable(allTimeStats)
                    if let busiest = snapshot.busiestDayOfWeek {
                        Text("\u{00B7} \(busiest.name)s")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("All time: \(snapshot.totalMessages) messages, \(snapshot.totalSessions) sessions")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var trendColor: Color {
        switch snapshot.trendDirection {
        case .up: return .orange
        case .down: return .green
        case .flat: return .secondary
        }
    }
}
