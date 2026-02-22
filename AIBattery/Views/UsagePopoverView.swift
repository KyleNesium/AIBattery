import Combine
import SwiftUI

public struct UsagePopoverView: View {
    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject private var accountStore: AccountStore
    @State private var showSettings = false
    @State private var isAddingAccount = false
    @AppStorage(UserDefaultsKeys.metricMode) private var metricModeRaw: String = "5h"

    public init(viewModel: UsageViewModel) {
        self.viewModel = viewModel
        self.accountStore = OAuthManager.shared.accountStore
    }

    private var metricMode: MetricMode {
        get { MetricMode(rawValue: metricModeRaw) ?? .fiveHour }
    }

    public var body: some View {
        if isAddingAccount {
            AuthView(
                oauthManager: OAuthManager.shared,
                isAddingAccount: true,
                onCancel: { isAddingAccount = false }
            )
            .onReceive(accountStore.$accounts) { newAccounts in
                // Auth completed for new account — switch back to main view
                if newAccounts.count > 1 && isAddingAccount {
                    isAddingAccount = false
                    Task { await viewModel.refresh() }
                }
            }
        } else {
            mainContent
        }
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection

            Divider()

            if showSettings {
                SettingsRow(
                    viewModel: viewModel,
                    accountStore: accountStore,
                    onAddAccount: { isAddingAccount = true }
                )
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

    private var accounts: [AccountRecord] {
        accountStore.accounts
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text("✦ AI Battery")
                    .font(.headline)
                accountPicker
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
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Account picker — always visible. Shows active account name with dropdown
    /// to switch accounts or add a new one.
    private var accountPicker: some View {
        Menu {
            let activeId = accountStore.activeAccountId
            ForEach(accounts) { account in
                Button(action: {
                    viewModel.switchAccount(to: account.id)
                }) {
                    HStack {
                        Text(accountLabel(account))
                        if account.id == activeId {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            if accountStore.canAddAccount {
                Divider()
                Button(action: { isAddingAccount = true }) {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("Add Account")
                    }
                }
            }
        } label: {
            let active = accountStore.activeAccount
            Text(accountPickerLabel(active))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Switch account")
    }

    /// Label for the account picker button. Shows identity parts for single
    /// account, org/display name for multi.
    private func accountPickerLabel(_ active: AccountRecord?) -> String {
        if accounts.count > 1 {
            return active.map { accountLabel($0) } ?? "Account"
        }
        // Single account — show richer identity like before
        guard let active else { return "Account" }
        var parts: [String] = []
        if let name = active.displayName, !name.isEmpty { parts.append(name) }
        if let org = active.organizationName, !org.isEmpty {
            let isDefault = active.displayName.map {
                org == "\($0)\u{2018}s Individual Org" || org == "\($0)'s Individual Org"
            } ?? false
            if !isDefault { parts.append(org) }
        }
        return parts.isEmpty ? "Account" : parts.joined(separator: " · ")
    }

    /// Short label for an account in the picker.
    private func accountLabel(_ account: AccountRecord) -> String {
        if let org = account.organizationName, !org.isEmpty { return org }
        if let name = account.displayName, !name.isEmpty { return name }
        return "Account"
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

                // Logout (active account)
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
                .accessibilityHint("Sign out of active Claude account")

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

/// Inline settings for account names, refresh rate, and notifications.
private struct SettingsRow: View {
    let viewModel: UsageViewModel
    @ObservedObject var accountStore: AccountStore
    let onAddAccount: () -> Void
    @AppStorage(UserDefaultsKeys.refreshInterval) private var refreshInterval: Double = 60
    @AppStorage(UserDefaultsKeys.tokenWindowDays) private var tokenWindowDays: Double = 0
    @AppStorage(UserDefaultsKeys.alertClaudeAI) private var alertClaudeAI: Bool = false
    @AppStorage(UserDefaultsKeys.alertClaudeCode) private var alertClaudeCode: Bool = false
    @AppStorage(UserDefaultsKeys.launchAtLogin) private var launchAtLogin: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Settings")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            // Per-account names
            ForEach(accountStore.accounts) { account in
                accountNameRow(account)
            }

            if accountStore.canAddAccount {
                HStack(spacing: 8) {
                    Spacer().frame(width: 50)
                    Button(action: onAddAccount) {
                        HStack(spacing: 3) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 10))
                            Text("Add Account")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .accessibilityLabel("Add another Claude account")
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

            // Launch at Login
            HStack(spacing: 8) {
                Text("Startup")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .onAppear {
                        if #available(macOS 13.0, *) {
                            launchAtLogin = LaunchAtLoginManager.isEnabled
                        }
                    }
                    .onChange(of: launchAtLogin) { newValue in
                        if #available(macOS 13.0, *) {
                            LaunchAtLoginManager.setEnabled(newValue)
                        }
                    }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Editable name row for a single account.
    private func accountNameRow(_ account: AccountRecord) -> some View {
        let isActive = account.id == accountStore.activeAccountId
        let label = accountStore.accounts.count > 1
            ? (isActive ? "Active" : "Account")
            : "Name"
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
                TextField("Your name", text: nameBinding(for: account.id))
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                if accountStore.accounts.count > 1 {
                    Button(action: {
                        OAuthManager.shared.signOut(accountId: account.id)
                    }) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove this account")
                    .accessibilityLabel("Remove account \(account.displayName ?? "")")
                }
            }
            if let org = account.organizationName, !org.isEmpty {
                Text(org)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 58)
            }
        }
    }

    /// Two-way binding that reads/writes `displayName` on the AccountRecord.
    private func nameBinding(for accountId: String) -> Binding<String> {
        Binding(
            get: {
                accountStore.accounts.first { $0.id == accountId }?.displayName ?? ""
            },
            set: { newValue in
                let clamped = String(newValue.prefix(30))
                OAuthManager.shared.updateAccountMetadata(
                    accountId: accountId,
                    displayName: clamped
                )
            }
        )
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

