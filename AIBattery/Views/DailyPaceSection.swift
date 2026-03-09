import SwiftUI

/// Shows the daily pace metric: today's messages as a percentage of the 7-day average.
struct DailyPaceSection: View {
    let snapshot: UsageSnapshot

    private var pacePercent: Double {
        snapshot.percent(for: .dailyPace)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header row
            HStack {
                Text("Daily Pace")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(Int(pacePercent))%")
                    .font(.system(.subheadline, design: .monospaced).bold())
                    .foregroundStyle(ThemeColors.dailyPaceColor(percent: pacePercent))
            }

            // Progress bar (0–200% scale, 100% midpoint)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 3)
                        .fill(ThemeColors.trackFill)

                    // Fill (capped at bar width, scale is 0–200%)
                    let fillFraction = min(pacePercent / 200.0, 1.0)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(ThemeColors.dailyPaceColor(percent: pacePercent))
                        .frame(width: geo.size.width * fillFraction)

                    // 100% midpoint marker
                    Rectangle()
                        .fill(ThemeColors.tertiaryLabel)
                        .frame(width: 1)
                        .offset(x: geo.size.width * 0.5)
                }
            }
            .frame(height: 6)
            .accessibilityValue("\(Int(pacePercent)) percent of daily average")

            // Stats row
            HStack {
                Text("Today: \(snapshot.todayMessages) msgs")
                    .font(.caption)
                    .foregroundStyle(ThemeColors.secondaryLabel)

                Text("\u{00B7}")
                    .foregroundStyle(ThemeColors.tertiaryLabel)

                Text("Avg: \(snapshot.dailyAverage) msgs/day")
                    .font(.caption)
                    .foregroundStyle(ThemeColors.secondaryLabel)

                Spacer()

                // Trend arrow
                Text(snapshot.trendDirection.symbol)
                    .font(.caption)
                    .foregroundStyle(ThemeColors.trendColor(snapshot.trendDirection))
                    .accessibilityLabel("Trend \(snapshot.trendDirection.accessibilityLabel)")
            }

            // Busiest day insight
            if let busiest = snapshot.busiestDayOfWeek {
                Text("Busiest: \(busiest.name) (\(busiest.averageCount) avg)")
                    .font(.caption2)
                    .foregroundStyle(ThemeColors.tertiaryLabel)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Daily pace: \(Int(pacePercent)) percent. Today \(snapshot.todayMessages) messages, average \(snapshot.dailyAverage) per day")
    }
}
