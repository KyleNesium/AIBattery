import SwiftUI

public struct MenuBarLabel: View {
    @ObservedObject var viewModel: UsageViewModel
    @AppStorage(UserDefaultsKeys.metricMode) private var metricModeRaw: String = "5h"
    @AppStorage(UserDefaultsKeys.autoMetricMode) private var autoMetricMode: Bool = false
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

    /// Whether the user is currently throttled and we have a reset date to count down to.
    private var throttleResetDate: Date? {
        guard let rateLimits = viewModel.snapshot?.rateLimits,
              rateLimits.isThrottled else { return nil }
        return rateLimits.bindingReset
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(spacing: 4) {
                MenuBarIcon(requestsPercent: displayPercent)

                Group {
                    if let resetDate = throttleResetDate {
                        Text(RateLimitUsage.countdownText(to: resetDate, from: context.date))
                    } else {
                        Text("\(Int(displayPercent))%")
                    }
                }
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .contentTransition(reduceMotion ? .identity : .numericText())
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: Int(displayPercent * 10))
                .opacity(isStale ? 0.5 : 1.0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(throttleAccessibilityLabel(at: context.date))
            .accessibilityValue(isStale ? "Data may be stale" : "Up to date")
        }
    }

    private func throttleAccessibilityLabel(at date: Date) -> String {
        if let resetDate = throttleResetDate {
            return "AI Battery rate limited, resets in \(RateLimitUsage.countdownText(to: resetDate, from: date))"
        }
        return "AI Battery usage \(Int(displayPercent)) percent"
    }
}
