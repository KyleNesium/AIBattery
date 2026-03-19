import SwiftUI

public struct UsagePopoverView: View {
    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject private var accountStore: AccountStore
    @State private var showSettings = false
    @State private var isAddingAccount = false
    @AppStorage(UserDefaultsKeys.metricMode) private var metricModeRaw: String = "5h"
    @AppStorage(UserDefaultsKeys.autoMetricMode) private var autoMetricMode: Bool = false
    #if ENABLE_VERSION_CHECKER
    @State private var updateCheckMessage: String?
    @State private var updateCheckDismissTask: Task<Void, Never>?
    @State private var updateBannerDismissed = false
    #endif
    @State private var accountCountAtAddStart = 0
    @State private var showLogoutConfirm = false
    @State private var logoutRevertTask: Task<Void, Never>?

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

    /// Read-only binding that reflects the auto-resolved mode in the segmented picker.
    private var autoResolvedBinding: Binding<String> {
        Binding(
            get: { viewModel.snapshot?.autoResolvedMode.rawValue ?? metricModeRaw },
            set: { _ in } // Picker is disabled in auto mode — no-op
        )
    }

    public var body: some View {
        if isAddingAccount {
            AuthView(
                oauthManager: OAuthManager.shared,
                isAddingAccount: true,
                onCancel: { isAddingAccount = false }
            )
            .onAppear { accountCountAtAddStart = accountStore.accounts.count }
            .onReceive(accountStore.$accounts) { newAccounts in
                // Auth completed for new account — detect actual addition, not initial publish
                if newAccounts.count > accountCountAtAddStart && isAddingAccount {
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
                metricToggle

                // Show inline error when rate limits unavailable (API not reachable)
                if snapshot.rateLimits == nil, let error = viewModel.errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(Typography.tinyLabel)
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(Typography.tinyLabel)
                            .foregroundStyle(ThemeColors.secondaryLabel)
                        Spacer()
                        Button("Retry") {
                            Task { await viewModel.refresh() }
                        }
                        .font(Typography.tinyLabel)
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                    }
                    .copyable(error)
                    .padding(.horizontal, Spacing.sectionHorizontal)
                    .padding(.vertical, Spacing.section)
                    Divider()
                }

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
                        } else {
                            idleFilteredEmptyState
                            Divider()
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: metricModeRaw)

                ProjectUsageGate(snapshot: snapshot)
                InsightsGate(snapshot: snapshot)

            } else if viewModel.isLoading {
                // First load — show minimal loading state
                HStack {
                    Spacer()
                    Text("Loading...")
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                    Spacer()
                }
                .frame(height: 40)
            } else if let error = viewModel.errorMessage {
                errorView(error)
            } else {
                emptyView
            }

            Divider()
            footerSection
        }
        .frame(width: Layout.popoverWidth)
        .contentShape(Rectangle())
        .overlay {
            TutorialOverlay(hasData: viewModel.snapshot != nil)
        }
        .onAppear { recomputeOrderedModes() }
        .onChange(of: metricModeRaw) { _ in recomputeOrderedModes() }
        .onDisappear {
            logoutRevertTask?.cancel()
            #if ENABLE_VERSION_CHECKER
            updateCheckDismissTask?.cancel()
            #endif
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "sparkle")
                    .font(Typography.heroValue)
                    .foregroundStyle(.primary)
                Text("AI Battery")
                    .font(Typography.sectionHeader)
                    .fixedSize()
                accountPicker
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                #if ENABLE_VERSION_CHECKER
                Text("v\(VersionChecker.currentAppVersion)")
                    .font(Typography.monoTiny)
                    .foregroundStyle(ThemeColors.tertiaryLabel)
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
                        .font(Typography.bodyLabel)
                }
                .buttonStyle(.plain)
                .foregroundStyle(
                    viewModel.availableUpdate != nil ? .yellow
                    : updateCheckMessage != nil ? .green
                    : .secondary
                )
                .help(viewModel.availableUpdate.map { "v\($0.version) available" } ?? "Check for updates")
                .accessibilityLabel(viewModel.availableUpdate.map { "Version \($0.version) available" } ?? "Check for updates")
                #else
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0")")
                    .font(Typography.monoTiny)
                    .foregroundStyle(ThemeColors.tertiaryLabel)
                #endif
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showSettings.toggle() } }) {
                    Image(systemName: "gearshape")
                        .font(Typography.bodyLabel)
                }
                .buttonStyle(.plain)
                .foregroundStyle(showSettings ? .primary : .secondary)
                .help("Settings")
                .accessibilityLabel("Settings")
                .accessibilityHint(showSettings ? "Close settings" : "Open settings")
            }

            #if ENABLE_VERSION_CHECKER
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
                                .font(Typography.tinyLabel)
                                .foregroundStyle(.yellow)
                            Text("v\(update.version)")
                                .font(Typography.tinyLabel)
                                .foregroundStyle(.secondary)
                            Image(systemName: "arrow.up.right")
                                .font(Typography.decorativeIcon)
                                .foregroundStyle(ThemeColors.tertiaryLabel)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Version \(update.version) release notes")
                    Button(action: {
                        #if ENABLE_SPARKLE
                        if SparkleUpdateService.shared.canCheckForUpdates {
                            SparkleUpdateService.shared.checkForUpdates()
                        } else if let url = URL(string: update.url) {
                            NSWorkspace.shared.open(url)
                        }
                        #else
                        if let url = URL(string: update.url) {
                            NSWorkspace.shared.open(url)
                        }
                        #endif
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.down.circle")
                                .font(Typography.monoTiny)
                            Text("Install Update")
                                .font(Typography.tinyLabel)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .accessibilityLabel("Install update version \(update.version)")
                    Spacer()
                    Button(action: { updateBannerDismissed = true }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(Typography.heroTitle)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss")
                    .accessibilityLabel("Dismiss update banner")
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.yellow.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.yellow.opacity(0.35), lineWidth: 1)
                        )
                )
                .padding(.horizontal, -2)
                .transition(.opacity)
            } else if let msg = updateCheckMessage {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(Typography.tinyLabel)
                        .foregroundStyle(.green)
                    Text(msg)
                        .font(Typography.tinyLabel)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }
            #endif
        }
        .padding(.horizontal, Spacing.sectionHorizontal)
        .padding(.vertical, Spacing.section)
    }

    /// Account picker — shows display name if set, otherwise "User N".
    private var accountPicker: some View {
        Menu {
            let activeId = accountStore.activeAccountId
            ForEach(Array(accountStore.accounts.enumerated()), id: \.element.id) { index, account in
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
            if let activeIndex = accountStore.accounts.firstIndex(where: { $0.id == accountStore.activeAccountId }) {
                Text(accountLabel(accountStore.accounts[activeIndex], index: activeIndex))
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("Account")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: 80)
        .accessibilityLabel("Switch account")
        .accessibilityHint("Select which Claude account to display")
    }

    /// Label for an account: display name if set, otherwise "User N".
    private func accountLabel(_ account: AccountRecord, index: Int) -> String {
        if let name = account.displayName, !name.isEmpty { return name }
        return "User \(index + 1)"
    }

    private var loadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Fetching usage data...")
                .font(Typography.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title3)
                .foregroundStyle(ThemeColors.caution)
            Text(message)
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            Button(action: { Task { await viewModel.refresh() } }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(Typography.monoTiny)
                    Text("Retry")
                        .font(Typography.caption)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
            .accessibilityHint("Retry loading usage data")
        }
        .padding(.horizontal, Spacing.sectionHorizontal)
        .frame(maxWidth: .infinity)
        .frame(height: 100)
    }

    private var emptyView: some View {
        VStack(spacing: 4) {
            Text("No Claude Code data found")
                .font(Typography.caption)
                .foregroundStyle(.secondary)
            Text("Start a Claude Code session to populate usage data.\nData appears automatically once Claude Code is running.")
                .font(Typography.tinyLabel)
                .foregroundStyle(ThemeColors.tertiaryLabel)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Spacing.sectionHorizontal)
        .frame(maxWidth: .infinity)
        .frame(height: 80)
    }

    private var idleFilteredEmptyState: some View {
        VStack(spacing: 4) {
            Text("No active sessions")
                .font(Typography.caption)
                .foregroundStyle(.secondary)
            let idleMinutes = Int(UserDefaults.standard.double(forKey: UserDefaultsKeys.idleSessionMinutes))
            if idleMinutes > 0 {
                Text("Idle cutoff: \(idleMinutes)m")
                    .font(Typography.tinyLabel)
                    .foregroundStyle(ThemeColors.tertiaryLabel)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    /// Cached ordered modes — avoids allocating a new array on every body evaluation.
    @State private var cachedOrderedModes: [MetricMode] = MetricMode.allCases
    private var orderedModes: [MetricMode] { cachedOrderedModes }

    private func recomputeOrderedModes() {
        cachedOrderedModes = [metricMode] + MetricMode.allCases.filter { $0 != metricMode }
    }


    private var metricToggle: some View {
        HStack(spacing: 8) {
            autoModeButton

            Picker("", selection: autoMetricMode ? autoResolvedBinding : $metricModeRaw) {
                ForEach(MetricMode.allCases, id: \.rawValue) { mode in
                    Text(mode.shortLabel).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .opacity(autoMetricMode ? 0.55 : 1.0)
            .disabled(autoMetricMode)
            .accessibilityLabel("Metric mode")
            .accessibilityHint("Switch between 5-hour, 7-day, and context health views")
            .help(autoMetricMode ? "Disabled while auto mode is active" : "Select primary metric for menu bar display")
        }
        .padding(.horizontal, Spacing.sectionHorizontal)
        .padding(.vertical, Spacing.section)
        .background(ThemeColors.badgeFill)
    }

    private var autoModeButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                autoMetricMode.toggle()
            }
        } label: {
            Text("A")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(autoMetricMode ? Color.green : .secondary.opacity(0.5))
                .frame(width: 20, height: 20)
                .background(
                    Circle()
                        .fill(autoMetricMode ? Color.green.opacity(0.15) : Color.clear)
                )
                .overlay(
                    Circle()
                        .stroke(autoMetricMode ? Color.green.opacity(0.6) : Color.secondary.opacity(0.2), lineWidth: 1.5)
                )
                .shadow(color: autoMetricMode ? Color.green.opacity(0.5) : .clear, radius: 4)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Auto mode")
        .accessibilityValue(autoMetricMode ? "On" : "Off")
        .accessibilityHint("Automatically shows the highest usage metric")
        .help(autoMetricMode ? "Auto mode: showing highest metric" : "Enable auto mode")
        .onChange(of: autoMetricMode) { active in
            announceAutoMode(active)
        }
    }

    private func announceAutoMode(_ active: Bool) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: "Auto mode \(active ? "on" : "off")"]
        )
    }

    private var footerSection: some View {
        VStack(spacing: 6) {
            // Links row
            HStack(spacing: 10) {
                // Usage Dashboard
                FooterLink(
                    icon: "chart.bar",
                    label: "Usage",
                    tooltip: "Open usage dashboard in browser"
                ) {
                    if let url = URL(string: "https://platform.claude.com/usage") {
                        NSWorkspace.shared.open(url)
                    }
                }

                // Status Page — colored dot acts as status indicator
                FooterLink(
                    label: "Status",
                    tooltip: statusTooltip,
                    accessibilityLabel: "System status: \(statusTooltip)"
                ) {
                    if let url = URL(string: StatusChecker.statusPageBaseURL) {
                        NSWorkspace.shared.open(url)
                    }
                } leading: {
                    Circle()
                        .fill(statusColor)
                        .frame(width: Layout.dotSizeSmall, height: Layout.dotSizeSmall)
                }

                Spacer()

                // Logout (active account) — two-tap confirmation
                Button(action: {
                    if showLogoutConfirm {
                        logoutRevertTask?.cancel()
                        OAuthManager.shared.signOut()
                        showLogoutConfirm = false
                    } else {
                        showLogoutConfirm = true
                        logoutRevertTask?.cancel()
                        logoutRevertTask = Task {
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            guard !Task.isCancelled else { return }
                            showLogoutConfirm = false
                        }
                    }
                }) {
                    HStack(spacing: 2) {
                        Image(systemName: showLogoutConfirm ? "exclamationmark.triangle" : "rectangle.portrait.and.arrow.right")
                            .font(Typography.monoTiny)
                        Text(showLogoutConfirm ? "Confirm?" : "Logout")
                            .font(Typography.tinyLabel)
                    }
                    .fixedSize()
                }
                .buttonStyle(.plain)
                .foregroundStyle(showLogoutConfirm ? .red : .secondary)
                .animation(.easeInOut(duration: 0.15), value: showLogoutConfirm)
                .accessibilityLabel(showLogoutConfirm ? "Confirm logout" : "Logout")
                .accessibilityHint("Sign out of active Claude account")

                // Quit
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    HStack(spacing: 2) {
                        Image(systemName: "xmark.circle")
                            .font(Typography.monoTiny)
                        Text("Quit")
                            .font(Typography.tinyLabel)
                    }
                    .fixedSize()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Quit (⌘Q)")
                .accessibilityLabel("Quit AI Battery")
            }

            // Active incident banner replaces timestamp when visible
            if let names = viewModel.systemStatus?.incidentNames, !names.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(Typography.tinyLabel)
                        .foregroundStyle(statusColor)
                    MarqueeText(texts: names, color: statusColor)
                }
            } else {
                HStack {
                    Spacer()
                    if viewModel.isLoading {
                        ProgressView()
                            .scaleEffect(0.4)
                            .frame(width: 10, height: 10)
                    }
                    if let lastFetch = viewModel.lastFreshFetch {
                        TimelineView(.periodic(from: .now, by: 10)) { _ in
                            Text("Updated \(Self.relativeTime(lastFetch))")
                                .font(Typography.monoTiny)
                                .foregroundStyle(ThemeColors.tertiaryLabel)
                                .help("Last fetched: \(Self.absoluteTime(lastFetch))")
                        }
                    } else if viewModel.isLoading {
                        Text("Loading...")
                            .font(Typography.monoTiny)
                            .foregroundStyle(ThemeColors.tertiaryLabel)
                    }
                }
            }

        }
        .padding(.horizontal, Spacing.sectionHorizontal)
        .padding(.vertical, Spacing.section)
    }

    private var systemIndicator: StatusIndicator? {
        viewModel.systemStatus?.indicator
    }

    private var statusColor: Color {
        guard let indicator = systemIndicator else { return .gray }
        return ThemeColors.statusColor(indicator)
    }

    private static func relativeTime(_ date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 5 { return "just now" }
        if elapsed < 60 { return "\(Int(elapsed))s ago" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))m ago" }
        return "\(Int(elapsed / 3600))h ago"
    }

    private static let absoluteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .medium
        f.dateStyle = .none
        return f
    }()

    private static func absoluteTime(_ date: Date) -> String {
        absoluteFormatter.string(from: date)
    }

    private var statusTooltip: String {
        switch systemIndicator {
        case .operational: return "All systems operational"
        case .degradedPerformance: return "Degraded performance"
        case .partialOutage: return "Partial outage"
        case .majorOutage: return "Major outage"
        case .maintenance: return "Under maintenance"
        case .unknown, .none: return "Check system status"
        }
    }
}
