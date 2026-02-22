import SwiftUI

public struct MenuBarLabel: View {
    @ObservedObject var viewModel: UsageViewModel
    @AppStorage(UserDefaultsKeys.orgName) private var storedOrgName: String = ""
    @AppStorage(UserDefaultsKeys.displayName) private var storedDisplayName: String = ""
    @AppStorage(UserDefaultsKeys.metricMode) private var metricModeRaw: String = "5h"
    @AppStorage(UserDefaultsKeys.menuBarDecimal) private var menuBarDecimal: Bool = false

    public init(viewModel: UsageViewModel) {
        self.viewModel = viewModel
    }

    private var metricMode: MetricMode {
        MetricMode(rawValue: metricModeRaw) ?? .fiveHour
    }

    /// The percentage to show, driven by the selected metric mode.
    private var displayPercent: Double {
        viewModel.snapshot?.percent(for: metricMode) ?? 0
    }

    /// Short org label for menu bar — shows real org name, hides default individual org.
    private var orgLabel: String? {
        let org = viewModel.snapshot?.organizationName
            ?? (storedOrgName.isEmpty ? nil : storedOrgName)
        guard let org, !org.isEmpty else { return nil }
        let name = viewModel.snapshot?.displayName
            ?? (storedDisplayName.isEmpty ? nil : storedDisplayName)
        if let name {
            if org == "\(name)\u{2018}s Individual Org" || org == "\(name)'s Individual Org" {
                return nil
            }
        }
        return org
    }

    /// Data is considered stale if the last fresh fetch was more than 5 minutes ago.
    private var isStale: Bool {
        guard let lastFetch = viewModel.lastFreshFetch else { return false }
        return Date().timeIntervalSince(lastFetch) > 300
    }

    public var body: some View {
        HStack(spacing: 4) {
            MenuBarIcon(requestsPercent: displayPercent)

            Text(menuBarDecimal ? String(format: "%.1f%%", displayPercent) : "\(Int(displayPercent))%")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.4), value: Int(displayPercent * 10))
                .opacity(isStale ? 0.5 : 1.0)

            if let org = orgLabel {
                Text("·")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text(org)
                    .font(.system(size: 10))
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("AI Battery usage \(Int(displayPercent)) percent\(orgLabel.map { ", \($0)" } ?? "")")
        .accessibilityValue(isStale ? "Data may be stale" : "Up to date")
    }
}
