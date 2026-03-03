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

    /// Countdown text when throttled, or nil for normal percentage display.
    private var throttleCountdown: String? {
        guard let rateLimits = viewModel.snapshot?.rateLimits,
              rateLimits.isThrottled,
              let resetDate = rateLimits.bindingReset else { return nil }
        return RateLimitUsage.countdownText(to: resetDate)
    }

    private var displayText: String {
        throttleCountdown ?? "\(Int(displayPercent))%"
    }

    public var body: some View {
        HStack(spacing: 4) {
            MenuBarIcon(requestsPercent: displayPercent)

            Text(displayText)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .contentTransition(reduceMotion ? .identity : .numericText())
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: Int(displayPercent * 10))
                .opacity(isStale ? 0.5 : 1.0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(throttleCountdown != nil
            ? "AI Battery rate limited, resets in \(displayText)"
            : "AI Battery usage \(Int(displayPercent)) percent")
        .accessibilityValue(isStale ? "Data may be stale" : "Up to date")
    }
}
