import SwiftUI

// MARK: - Gate views (check data availability, sections own their collapsed state)

/// Shows token usage section when token data exists.
struct TokenUsageGate: View {
    let snapshot: UsageSnapshot

    var body: some View {
        if snapshot.totalTokens > 0 {
            TokenUsageSection(
                snapshot: snapshot,
                activeModelId: snapshot.tokenHealth?.model
            )
            Divider()
        }
    }
}

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

/// Shows activity chart when activity data exists.
struct ActivityChartGate: View {
    let snapshot: UsageSnapshot

    var body: some View {
        if !snapshot.dailyActivity.isEmpty || !snapshot.todayHourCounts.isEmpty {
            ActivityChartView(
                dailyActivity: snapshot.dailyActivity,
                todayHourCounts: snapshot.todayHourCounts,
                snapshot: snapshot
            )
            Divider()
        }
    }
}
