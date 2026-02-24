import SwiftUI

public struct MenuBarLabel: View {
    @ObservedObject var viewModel: UsageViewModel
    @AppStorage(UserDefaultsKeys.metricMode) private var metricModeRaw: String = "5h"
    @AppStorage(UserDefaultsKeys.autoMetricMode) private var autoMetricMode: Bool = false
    @AppStorage(UserDefaultsKeys.showSparkline) private var showSparkline: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(viewModel: UsageViewModel) {
        self.viewModel = viewModel
    }

    private var metricMode: MetricMode {
        if autoMetricMode, let snapshot = viewModel.snapshot {
            return snapshot.autoResolvedMode
        }
        return MetricMode(rawValue: metricModeRaw) ?? .fiveHour
    }

    /// The percentage to show, driven by the selected metric mode.
    private var displayPercent: Double {
        viewModel.snapshot?.percent(for: metricMode) ?? 0
    }

    /// Data is considered stale if the last fresh fetch was more than 5 minutes ago.
    private var isStale: Bool {
        guard let lastFetch = viewModel.lastFreshFetch else { return false }
        return Date().timeIntervalSince(lastFetch) > 300
    }

    public var body: some View {
        HStack(spacing: 4) {
            MenuBarIcon(requestsPercent: displayPercent)

            if showSparkline, let hourCounts = viewModel.snapshot?.hourCounts,
               !hourCounts.isEmpty {
                MenuBarSparkline(hourCounts: hourCounts)
            }

            Text("\(Int(displayPercent))%")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .contentTransition(reduceMotion ? .identity : .numericText())
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: Int(displayPercent * 10))
                .opacity(isStale ? 0.5 : 1.0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("AI Battery usage \(Int(displayPercent)) percent")
        .accessibilityValue(isStale ? "Data may be stale" : "Up to date")
    }
}
