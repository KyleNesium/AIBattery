import SwiftUI

public struct UsagePopoverView: View {
    @ObservedObject var viewModel: UsageViewModel
    @State private var showSettings = false
    @AppStorage(UserDefaultsKeys.orgName) private var storedOrgName: String = ""
    @AppStorage(UserDefaultsKeys.displayName) private var storedDisplayName: String = ""
    @AppStorage(UserDefaultsKeys.metricMode) private var metricModeRaw: String = "5h"

    public init(viewModel: UsageViewModel) {
        self.viewModel = viewModel
    }

    private var metricMode: MetricMode {
        get { MetricMode(rawValue: metricModeRaw) ?? .fiveHour }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection

            Divider()

            if showSettings {
                SettingsRow(viewModel: viewModel)
                Divider()
            }

            if let snapshot = viewModel.snapshot {
                // Metric mode toggle
                metricToggle
                Divider()

                // Sections reordered: selected metric first, then the other two
                ForEach(orderedModes, id: \.rawValue) { mode in
                    switch mode {
                    case .fiveHour:
                        if let limits = snapshot.rateLimits {
                            FiveHourBarSection(limits: limits)
                            Divider()
                        }
                    case .sevenDay:
                        if let limits = snapshot.rateLimits {
                            SevenDayBarSection(limits: limits)
                            Divider()
                        }
                    case .contextHealth:
                        if !snapshot.topSessionHealths.isEmpty {
                            TokenHealthSection(sessions: snapshot.topSessionHealths, onRefresh: {
                                Task { await viewModel.refresh() }
                            })
                            Divider()
                        } else if let health = snapshot.tokenHealth {
                            TokenHealthSection(health: health, onRefresh: {
                                Task { await viewModel.refresh() }
                            })
                            Divider()
                        }
                    }
                }

                if snapshot.totalTokens > 0 {
                    TokenUsageSection(
                        snapshot: snapshot,
                        activeModelId: snapshot.tokenHealth?.model
                    )
                    Divider()
                }

                if !snapshot.dailyActivity.isEmpty || !snapshot.hourCounts.isEmpty {
                    ActivityChartView(
                        dailyActivity: snapshot.dailyActivity,
                        hourCounts: snapshot.hourCounts
                    )
                    Divider()
                }

                if snapshot.totalMessages > 0 {
                    InsightsSection(snapshot: snapshot)
                }
            } else if viewModel.isLoading {
                loadingView
            } else if let error = viewModel.errorMessage {
                errorView(error)
            } else {
                emptyView
            }

            Divider()
            footerSection
        }
        .frame(width: 275)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text("✦ AI Battery")
                    .font(.headline)
                if let snapshot = viewModel.snapshot {
                    let identity = headerIdentityParts(snapshot)
                    if !identity.isEmpty {
                        Text(identity.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                }
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(showSettings ? .primary : .secondary)
                .help("Settings")
                .accessibilityLabel("Settings")
                .accessibilityHint(showSettings ? "Close settings" : "Open settings")
                Button(action: { Task { await viewModel.refresh() } }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Refresh")
                .accessibilityLabel("Refresh usage data")
            }

}
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var loadingView: some View {
        HStack {
            Spacer()
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading...")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(height: 80)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title3)
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await viewModel.refresh() } }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .accessibilityHint("Retry loading usage data")
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100)
    }

    private var emptyView: some View {
        VStack(spacing: 4) {
            Text("No Claude Code data found")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Start a Claude Code session to populate usage data.\nData appears automatically once Claude Code is running.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80)
    }

    /// Returns all metric modes with the selected one first.
    private var orderedModes: [MetricMode] {
        var modes = MetricMode.allCases
        modes.removeAll { $0 == metricMode }
        return [metricMode] + modes
    }

    private var metricToggle: some View {
        HStack {
            Spacer()
            Picker("", selection: $metricModeRaw) {
                ForEach(MetricMode.allCases, id: \.rawValue) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
            .accessibilityLabel("Metric mode")
            .accessibilityHint("Switch between 5-hour, 7-day, and context health views")
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    /// Identity parts shown next to the title: name + org.
    /// Reads @AppStorage directly so it updates live when user edits settings.
    private func headerIdentityParts(_ snapshot: UsageSnapshot) -> [String] {
        var parts: [String] = []
        let name = snapshot.displayName ?? (storedDisplayName.isEmpty ? nil : storedDisplayName)
        if let name, !name.isEmpty {
            parts.append(name)
        }
        let org = snapshot.organizationName ?? (storedOrgName.isEmpty ? nil : storedOrgName)
        if let org, !org.isEmpty {
            let isDefault = name.map {
                org == "\($0)\u{2018}s Individual Org" || org == "\($0)'s Individual Org"
            } ?? false
            if !isDefault {
                parts.append(org)
            }
        }
        return parts
    }

    private var footerSection: some View {
        VStack(spacing: 6) {
            // Links row
            HStack(spacing: 6) {
                // Usage Dashboard
                Button(action: {
                    if let url = URL(string: "https://platform.claude.com/usage") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack(spacing: 2) {
                        Image(systemName: "chart.bar")
                            .font(.system(size: 9))
                        Text("Usage")
                            .font(.caption2)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 6))
                    }
                    .fixedSize()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Open usage dashboard in browser")
                .accessibilityLabel("Open usage dashboard in browser")

                // Status Page — colored dot acts as status indicator
                Button(action: {
                    if let url = URL(string: "https://status.claude.com") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack(spacing: 2) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)
                        Text("Status")
                            .font(.caption2)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 6))
                    }
                    .fixedSize()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(statusTooltip)
                .accessibilityLabel("System status: \(statusTooltip)")
                .accessibilityHint("Open status page in browser")

                Spacer()

                // Logout
                Button(action: {
                    OAuthManager.shared.signOut()
                }) {
                    HStack(spacing: 2) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 9))
                        Text("Logout")
                            .font(.caption2)
                    }
                    .fixedSize()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Logout")
                .accessibilityHint("Sign out of your Claude account")

                // Quit
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    HStack(spacing: 2) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 9))
                        Text("Quit")
                            .font(.caption2)
                    }
                    .fixedSize()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Quit AI Battery")
            }

            // Active incident banner (if any)
            if let incident = viewModel.systemStatus?.incidentName {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(statusColor)
                    Text(incident)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            // Staleness indicator
            if let lastFetch = viewModel.lastFreshFetch {
                HStack(spacing: 3) {
                    if viewModel.isShowingCachedData {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 8))
                            .foregroundStyle(.orange)
                    }
                    Text(Self.stalenessLabel(lastFetch))
                        .font(.system(size: 9))
                        .foregroundStyle(viewModel.isShowingCachedData ? Color.orange : Color.gray.opacity(0.4))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.stalenessLabel(lastFetch) + (viewModel.isShowingCachedData ? ", showing cached data" : ""))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private static func stalenessLabel(_ date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 60 { return "Updated just now" }
        if elapsed < 3600 { return "Updated \(Int(elapsed / 60))m ago" }
        return "Updated \(Int(elapsed / 3600))h ago"
    }

    private var statusColor: Color {
        switch viewModel.systemStatus?.indicator {
        case .operational: return .green
        case .degradedPerformance: return .yellow
        case .partialOutage: return .orange
        case .majorOutage: return .red
        case .maintenance: return .blue
        case .unknown, .none: return .gray
        }
    }

    private var statusTooltip: String {
        switch viewModel.systemStatus?.indicator {
        case .operational: return "All systems operational"
        case .degradedPerformance: return "Degraded performance"
        case .partialOutage: return "Partial outage"
        case .majorOutage: return "Major outage"
        case .maintenance: return "Under maintenance"
        case .unknown, .none: return "Check system status"
        }
    }
}

/// Inline settings for name, org, refresh rate, and notifications.
private struct SettingsRow: View {
    let viewModel: UsageViewModel
    @AppStorage(UserDefaultsKeys.orgName) private var orgName: String = ""
    @AppStorage(UserDefaultsKeys.displayName) private var displayName: String = ""
    @AppStorage(UserDefaultsKeys.refreshInterval) private var refreshInterval: Double = 60
    @AppStorage(UserDefaultsKeys.tokenWindowDays) private var tokenWindowDays: Double = 0
    @AppStorage(UserDefaultsKeys.alertClaudeAI) private var alertClaudeAI: Bool = false
    @AppStorage(UserDefaultsKeys.alertClaudeCode) private var alertClaudeCode: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Settings")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            // Name
            HStack(spacing: 8) {
                Text("Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
                TextField("Your name", text: $displayName)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onChange(of: displayName) { _ in
                        if displayName.count > 30 { displayName = String(displayName.prefix(30)) }
                    }
            }

            // Org
            HStack(spacing: 8) {
                Text("Org")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
                TextField("Organization name", text: $orgName)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onChange(of: orgName) { _ in
                        if orgName.count > 50 { orgName = String(orgName.prefix(50)) }
                    }
            }

            // Refresh interval
            VStack(spacing: 2) {
                HStack(spacing: 8) {
                    Text("Refresh")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .trailing)
                    Slider(value: $refreshInterval, in: 10...60, step: 5)
                        .onChange(of: refreshInterval) { _ in
                            viewModel.updatePollingInterval(refreshInterval)
                        }
                        .accessibilityLabel("Refresh interval")
                        .accessibilityValue("\(Int(refreshInterval)) seconds")
                    Text("\(Int(refreshInterval))s")
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 28, alignment: .trailing)
                }
                sliderMarks(labels: ["10s", "20s", "30s", "40s", "50s", "60s"], leadingPad: 50)
                Text("~3 tokens per poll")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 58)
            }

            // Models window (slider 1–8; 1–7 = days, 8 = all time stored as 0)
            VStack(spacing: 2) {
                HStack(spacing: 8) {
                    Text("Models")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .trailing)
                    Slider(value: modelsSliderBinding, in: 1...8, step: 1)
                        .accessibilityLabel("Models time window")
                        .accessibilityValue(tokenWindowDays > 0 ? "\(Int(tokenWindowDays)) days" : "All time")
                    Text(tokenWindowDays > 0 ? "\(Int(tokenWindowDays))d" : "All")
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 28, alignment: .trailing)
                }
                sliderMarks(labels: ["1d", "2d", "3d", "4d", "5d", "6d", "7d", "All"], leadingPad: 50)
                Text("Only show models used within period")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 58)
            }

            // Status alerts
            HStack(spacing: 8) {
                Text("Alerts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
                Toggle("Claude.ai", isOn: $alertClaudeAI)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .onChange(of: alertClaudeAI) { on in
                        if on { NotificationManager.shared.requestPermission() }
                    }
                Toggle("Claude Code", isOn: $alertClaudeCode)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .onChange(of: alertClaudeCode) { on in
                        if on { NotificationManager.shared.requestPermission() }
                    }
            }
            Text("Notify when service is down")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.leading, 58)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Maps slider position (1–8) ↔ stored value (1–7 days, 0 = all time).
    private var modelsSliderBinding: Binding<Double> {
        Binding(
            get: { tokenWindowDays > 0 ? tokenWindowDays : 8 },
            set: { tokenWindowDays = $0 >= 8 ? 0 : $0 }
        )
    }

    /// Tick mark labels displayed below a slider.
    private func sliderMarks(labels: [String], leadingPad: CGFloat) -> some View {
        HStack {
            Spacer().frame(width: leadingPad + 8) // label width + HStack spacing
            HStack(spacing: 0) {
                ForEach(Array(labels.enumerated()), id: \.offset) { i, label in
                    Text(label)
                        .font(.system(size: 8))
                        .foregroundStyle(.quaternary)
                    if i < labels.count - 1 {
                        Spacer()
                    }
                }
            }
            Spacer().frame(width: 36) // value label width + spacing
        }
    }
}

