import SwiftUI

public struct UsagePopoverView: View {
    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject private var accountStore: AccountStore
    @State private var showSettings = false
    @State private var isAddingAccount = false
    @AppStorage(UserDefaultsKeys.metricMode) private var metricModeRaw: String = "5h"
    @AppStorage(UserDefaultsKeys.autoMetricMode) private var autoMetricMode: Bool = false
    @State private var updateCheckMessage: String?
    @State private var updateCheckDismissTask: Task<Void, Never>?
    @State private var updateBannerDismissed = false

    public init(viewModel: UsageViewModel) {
        self.viewModel = viewModel
        self.accountStore = OAuthManager.shared.accountStore
    }

    private var metricMode: MetricMode {
        if autoMetricMode, let snapshot = viewModel.snapshot {
            return snapshot.autoResolvedMode
        }
        return MetricMode(rawValue: metricModeRaw) ?? .fiveHour
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
                .transition(.opacity.combined(with: .move(edge: .top)))
                Divider()
            }

            if let snapshot = viewModel.snapshot {
                // Metric mode toggle
                metricToggle
                Divider()

                // Sections reordered: selected metric first, then the other two.
                // Animation scoped here — only metric sections animate on mode change.
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
                .animation(.easeInOut(duration: 0.15), value: metricModeRaw)

                TokenUsageGate(snapshot: snapshot)
                ActivityChartGate(snapshot: snapshot)

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
        .overlay {
            TutorialOverlay(hasData: viewModel.snapshot != nil)
        }
        .onDisappear {
            updateCheckDismissTask?.cancel()
        }
    }

    private var accounts: [AccountRecord] {
        accountStore.accounts
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
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
                Text("v\(VersionChecker.currentAppVersion)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Button(action: {
                    if viewModel.availableUpdate != nil {
                        updateBannerDismissed = false
                    } else {
                        Task {
                            let result = await VersionChecker.shared.forceCheckForUpdate()
                            viewModel.availableUpdate = result
                            if result == nil {
                                updateCheckMessage = "Up to date"
                                updateCheckDismissTask?.cancel()
                                updateCheckDismissTask = Task {
                                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                                    guard !Task.isCancelled else { return }
                                    updateCheckMessage = nil
                                }
                            } else {
                                updateCheckMessage = nil
                            }
                        }
                    }
                }) {
                    Image(systemName: "arrow.up.circle")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(
                    viewModel.availableUpdate != nil ? .yellow
                    : updateCheckMessage != nil ? .green
                    : .secondary
                )
                .help(viewModel.availableUpdate.map { "v\($0.version) available" } ?? "Check for updates")
                .accessibilityLabel(viewModel.availableUpdate.map { "Version \($0.version) available" } ?? "Check for updates")
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showSettings.toggle() } }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(showSettings ? .primary : .secondary)
                .help("Settings")
                .accessibilityLabel("Settings")
                .accessibilityHint(showSettings ? "Close settings" : "Open settings")
            }

            // Update status message (appears/disappears below header row)
            if let update = viewModel.availableUpdate, !updateBannerDismissed {
                HStack(spacing: 6) {
                    Button(action: {
                        if let url = URL(string: update.url) {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                            Text("v\(update.version)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 6))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    Button(action: {
                        if SparkleUpdateService.shared.canCheckForUpdates {
                            SparkleUpdateService.shared.checkForUpdates()
                        } else if let url = URL(string: update.url) {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 9))
                            Text("Install Update")
                                .font(.caption2)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    Spacer()
                    Button(action: { updateBannerDismissed = true }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss")
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.yellow.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.yellow.opacity(0.25), lineWidth: 1)
                        )
                )
                .padding(.horizontal, -2)
                .transition(.opacity)
            } else if let msg = updateCheckMessage {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Text(msg)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Account picker — shows display name if set, otherwise "Account N".
    private var accountPicker: some View {
        Menu {
            let activeId = accountStore.activeAccountId
            ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.switchAccount(to: account.id)
                    }
                }) {
                    HStack {
                        Text(accountLabel(account, index: index))
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
            if let activeIndex = accounts.firstIndex(where: { $0.id == accountStore.activeAccountId }),
               let active = accountStore.activeAccount {
                Text(accountLabel(active, index: activeIndex))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("Account")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Switch account")
    }

    /// Label for an account: display name if set, otherwise "Account N".
    private func accountLabel(_ account: AccountRecord, index: Int) -> String {
        if let name = account.displayName, !name.isEmpty { return name }
        return "Account \(index + 1)"
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
                .foregroundStyle(ThemeColors.caution)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            Button("Retry") { Task { await viewModel.refresh() } }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .accessibilityHint("Retry loading usage data")
        }
        .padding(.horizontal, 16)
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
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 80)
    }

    /// Returns all metric modes with the selected one first.
    private var orderedModes: [MetricMode] {
        var modes = MetricMode.allCases
        modes.removeAll { $0 == metricMode }
        return [metricMode] + modes
    }

    @State private var autoGlowing = false

    private var metricToggle: some View {
        HStack(spacing: 0) {
            autoModeButton

            Spacer()
            Picker("", selection: $metricModeRaw) {
                ForEach(MetricMode.allCases, id: \.rawValue) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 190)
            .opacity(autoMetricMode ? 0.4 : 1.0)
            .disabled(autoMetricMode)
            .accessibilityLabel("Metric mode")
            .accessibilityHint("Switch between 5-hour, 7-day, and context health views")
            .help(autoMetricMode ? "Disabled while auto mode is active" : "Select primary metric for menu bar display")
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var autoModeButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                autoMetricMode.toggle()
            }
        } label: {
            Text("A")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(autoMetricMode ? Color.blue : .secondary.opacity(0.5))
                .frame(width: 20, height: 20)
                .background(
                    Circle()
                        .fill(autoMetricMode ? Color.blue.opacity(0.15) : Color.clear)
                )
                .overlay(
                    Circle()
                        .stroke(autoMetricMode ? Color.blue.opacity(autoGlowing ? 0.8 : 0.3) : Color.secondary.opacity(0.2), lineWidth: 1.5)
                        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: autoGlowing)
                )
                .shadow(
                    color: autoMetricMode ? Color.blue.opacity(autoGlowing ? 0.5 : 0.1) : .clear,
                    radius: autoGlowing ? 5 : 1
                )
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: autoGlowing)
                .padding(6)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Auto mode")
        .accessibilityValue(autoMetricMode ? "On" : "Off")
        .accessibilityHint("Automatically shows the highest usage metric")
        .help(autoMetricMode ? "Auto mode: showing highest metric" : "Enable auto mode")
        .onChange(of: autoMetricMode) { active in
            autoGlowing = active
        }
        .onAppear {
            autoGlowing = autoMetricMode
        }
    }

    private var footerSection: some View {
        VStack(spacing: 6) {
            // Links row
            HStack(spacing: 10) {
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
                    if let url = URL(string: StatusChecker.statusPageBaseURL) {
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
            if let names = viewModel.systemStatus?.incidentNames, !names.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(statusColor)
                    MarqueeText(texts: names, color: statusColor)
                }
            }

        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var statusColor: Color {
        guard let indicator = viewModel.systemStatus?.indicator else { return .gray }
        return ThemeColors.statusColor(indicator)
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

// MARK: - Gate views (own their @AppStorage to avoid parent redraws)

/// Shows token usage section only when the "Tokens" toggle is on.
private struct TokenUsageGate: View {
    @AppStorage(UserDefaultsKeys.showTokens) private var showTokens = true
    let snapshot: UsageSnapshot

    var body: some View {
        if showTokens && snapshot.totalTokens > 0 {
            TokenUsageSection(
                snapshot: snapshot,
                activeModelId: snapshot.tokenHealth?.model
            )
            Divider()
        }
    }
}

/// Shows activity chart only when the "Activity" toggle is on.
private struct ActivityChartGate: View {
    @AppStorage(UserDefaultsKeys.showActivity) private var showActivity = true
    let snapshot: UsageSnapshot

    var body: some View {
        if showActivity && (!snapshot.dailyActivity.isEmpty || !snapshot.hourCounts.isEmpty) {
            ActivityChartView(
                dailyActivity: snapshot.dailyActivity,
                hourCounts: snapshot.hourCounts,
                snapshot: snapshot
            )
            Divider()
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
    @AppStorage(UserDefaultsKeys.alertRateLimit) private var alertRateLimit: Bool = false
    @AppStorage(UserDefaultsKeys.rateLimitThreshold) private var rateLimitThreshold: Double = 80
    @AppStorage(UserDefaultsKeys.showCostEstimate) private var showCostEstimate: Bool = false
    @AppStorage(UserDefaultsKeys.showTokens) private var showTokens: Bool = true
    @AppStorage(UserDefaultsKeys.showActivity) private var showActivity: Bool = true
    @AppStorage(UserDefaultsKeys.colorblindMode) private var colorblindMode: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Settings")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            // Per-account names
            ForEach(Array(accountStore.accounts.enumerated()), id: \.element.id) { index, account in
                accountNameRow(account, index: index)
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

            // Display
            HStack(spacing: 8) {
                Text("Display")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
                Toggle("Tokens", isOn: $showTokens)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Toggle("Activity", isOn: $showActivity)
                    .toggleStyle(.checkbox)
                    .font(.caption)
            }
            HStack(spacing: 8) {
                Spacer().frame(width: 50)
                Toggle("Colorblind", isOn: $colorblindMode)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .help("Use colorblind-safe palette (blue/cyan/amber/purple)")
                Toggle("Cost*", isOn: $showCostEstimate)
                    .toggleStyle(.checkbox)
                    .font(.caption)
            }
            HStack(spacing: 8) {
                Spacer().frame(width: 50)
                Text("Cost* = equivalent API token rates")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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
                if alertClaudeAI || alertClaudeCode {
                    Button("Test") {
                        NotificationManager.shared.testAlerts()
                    }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(.blue)
                }
            }
            Text("Notify when service is down")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.leading, 58)

            // Rate limit alerts
            VStack(spacing: 2) {
                HStack(spacing: 8) {
                    Spacer()
                        .frame(width: 50)
                    Toggle("Rate Limit Notify", isOn: $alertRateLimit)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                }
                if alertRateLimit {
                    HStack(spacing: 8) {
                        Spacer()
                            .frame(width: 50)
                        Slider(value: $rateLimitThreshold, in: 50...95, step: 5)
                            .accessibilityLabel("Rate limit alert threshold")
                            .accessibilityValue("\(Int(rateLimitThreshold)) percent")
                        Text("\(Int(rateLimitThreshold))%")
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 28, alignment: .trailing)
                    }
                    sliderMarks(labels: ["50%", "60%", "70%", "80%", "90%", "95%"], leadingPad: 50)
                    Text("Notify when rate limit usage exceeds threshold")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 58)
                }
            }

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
    private func accountNameRow(_ account: AccountRecord, index: Int) -> some View {
        let isActive = account.id == accountStore.activeAccountId
        let label = accountStore.accounts.count > 1
            ? (isActive ? "Active" : "Account")
            : "Name"
        return HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
            TextField("Account \(index + 1)", text: nameBinding(for: account.id))
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
                .accessibilityLabel("Remove account \(index + 1)")
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

