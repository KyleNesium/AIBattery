import SwiftUI

// MARK: - Gate views (check data availability, sections own their collapsed state)

/// Shows project usage section when project data exists.
struct ProjectUsageGate: View {
    let snapshot: UsageSnapshot

    var body: some View {
        if !snapshot.projectTokens.isEmpty {
            ProjectUsageSection(snapshot: snapshot)
            Divider()
        }
    }
}

/// Shows insights (activity chart + cost + insight rows) when data exists.
struct InsightsGate: View {
    let snapshot: UsageSnapshot

    var body: some View {
        if !snapshot.dailyActivity.isEmpty || !snapshot.todayHourCounts.isEmpty || snapshot.totalTokens > 0 {
            InsightsView(
                dailyActivity: snapshot.dailyActivity,
                todayHourCounts: snapshot.todayHourCounts,
                snapshot: snapshot,
                activeModelId: snapshot.tokenHealth?.model
            )
            Divider()
        }
    }
}
