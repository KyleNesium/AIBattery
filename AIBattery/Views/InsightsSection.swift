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
                Text("\(snapshot.todayMessages) msgs \u{00B7} \(snapshot.todaySessions) sessions \u{00B7} \(snapshot.todayToolCalls) tools")
                    .font(.system(.caption, design: .monospaced))
            }

            // Totals
            HStack {
                Text("All Time")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(snapshot.totalMessages) msgs \u{00B7} \(snapshot.totalSessions) sessions")
                    .font(.system(.caption, design: .monospaced))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
