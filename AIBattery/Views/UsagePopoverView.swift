import SwiftUI

// MARK: - Deferred render state

/// Tracks whether the panel has completed its initial render pass.
/// Heavy sections gate on `hasAppeared` to defer rendering by one run-loop iteration.
struct DeferredRenderState {
    private(set) var hasAppeared: Bool = false

    mutating func appeared() {
        hasAppeared = true
    }

    mutating func disappeared() {
        hasAppeared = false
    }
}

// MARK: - UsagePopoverView

public struct UsagePopoverView: View {
    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject private var accountStore: AccountStore
    /// Popover width scales with system text size, capped to avoid overflow.
    @ScaledMetric(relativeTo: .body) private var scaledWidth: CGFloat = Layout.popoverWidth
    @State private var showSettings = false
    @State private var isAddingAccount = false
    @AppStorage(UserDefaultsKeys.metricMode) private var metricModeRaw: String = "5h"
    @AppStorage(UserDefaultsKeys.autoMetricMode) private var autoMetricMode: Bool = false
    @State private var accountCountAtAddStart = 0
    @State private var showLogoutConfirm = false
    @State private var logoutRevertTask: Task<Void, Never>?
    @State private var panelHasAppeared = false

    /// Cached ordered modes — avoids allocating a new array on every body evaluation.
    @State private var cachedOrderedModes: [MetricMode] = MetricMode.allCases
    private var orderedModes: [MetricMode] { cachedOrderedModes }

    public init(viewModel: UsageViewModel) {
        self.viewModel = viewModel
        self.accountStore = OAuthManager.shared.accountStore
    }

    private var metricMode: MetricMode {
        if autoMetricMode {
            return viewModel.resolvedMetricMode
        }
        return MetricMode(rawValue: metricModeRaw) ?? .fiveHour
    }

    /// Single stable binding for the metric mode picker.
    /// In auto mode: reads from snapshot's resolved mode, ignores writes (picker is disabled).
    /// In manual mode: reads/writes the raw AppStorage value.
    /// Using one binding avoids the SwiftUI AttributeGraph crash caused by swapping
    /// different Binding instances between evaluations of the same Picker.
    private var pickerBinding: Binding<String> {
        Binding(
            get: {
                if autoMetricMode {
                    return viewModel.resolvedMetricMode.rawValue
                }
                return metricModeRaw
            },
            set: { newValue in
                if !autoMetricMode {
                    metricModeRaw = newValue
                }
            }
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
            PopoverHeaderView(
                snapshot: viewModel.snapshot,
                accountStore: accountStore,
                showSettings: $showSettings,
                isAddingAccount: $isAddingAccount,
                onSwitchAccount: { accountId in
                    viewModel.switchAccount(to: accountId)
                },
                onUpdateFound: { update in
                    viewModel.availableUpdate = update
                },
                availableUpdate: viewModel.availableUpdate
            )

            if showSettings {
                SettingsRow(
                    viewModel: viewModel,
                    accountStore: accountStore,
                    onAddAccount: { isAddingAccount = true }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
                StyledDivider()
            } else if let snapshot = viewModel.snapshot {
                MetricToggleView(
                    pickerBinding: pickerBinding,
                    snapshot: snapshot
                )

                // Local estimate header — shown once when API rate limits are unavailable
                if snapshot.rateLimits == nil && snapshot.isUsingLocalEstimate {
                    HStack(spacing: Spacing.inner) {
                        Image(systemName: "chart.bar.fill")
                            .font(Typography.tinyLabel)
                            .foregroundStyle(ThemeColors.tertiaryLabel)
                        Text(LocalUsageEstimate.isCalibrated ? "Estimated from local data" : "Local token usage")
                            .font(Typography.tinyLabel)
                            .foregroundStyle(ThemeColors.secondaryLabel)
                        Spacer()
                        Button(action: {
                            if let url = URL(string: "https://github.com/KyleNesium/AIBattery/issues/141") {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            HStack(spacing: Spacing.inner) {
                                Image(systemName: "info.circle")
                                    .font(Typography.decorativeIcon)
                                Image(systemName: "arrow.up.right")
                                    .font(Typography.decorativeIcon)
                            }
                            .foregroundStyle(ThemeColors.tertiaryLabel)
                        }
                        .buttonStyle(.plain)
                        .help("Anthropic removed usage headers from their API. Tap for details.")
                    }
                    .padding(.horizontal, Spacing.sectionHorizontal)
                    .padding(.top, Spacing.section)
                }

                // All 3 sections always render (selected mode first via orderedModes).
                ForEach(orderedModes, id: \.rawValue) { mode in
                    switch mode {
                    case .fiveHour:
                        if let limits = snapshot.rateLimits {
                            FiveHourBarSection(limits: limits, source: snapshot.rateLimitSource)
                            StyledDivider()
                        } else if snapshot.isUsingLocalEstimate {
                            LocalEstimateSection(
                                fiveHourTokens: snapshot.fiveHourTokens,
                                sevenDayTokens: snapshot.sevenDayTokens,
                                window: .fiveHour
                            )
                            StyledDivider()
                        } else if let stdLimits = snapshot.standardLimits {
                            StandardLimitsSection(limits: stdLimits)
                            StyledDivider()
                        }
                    case .sevenDay:
                        if let limits = snapshot.rateLimits {
                            SevenDayBarSection(limits: limits, source: snapshot.rateLimitSource)
                            StyledDivider()
                        } else if snapshot.isUsingLocalEstimate {
                            LocalEstimateSection(
                                fiveHourTokens: snapshot.fiveHourTokens,
                                sevenDayTokens: snapshot.sevenDayTokens,
                                window: .sevenDay
                            )
                            StyledDivider()
                        } else if let stdLimits = snapshot.standardLimits {
                            StandardLimitsSection(limits: stdLimits)
                            StyledDivider()
                        }
                    case .contextHealth:
                        if !snapshot.topSessionHealths.isEmpty {
                            TokenHealthSection(sessions: snapshot.topSessionHealths, onRefresh: {
                                Task { await viewModel.refresh() }
                            })
                            StyledDivider()
                        } else if let health = snapshot.tokenHealth {
                            TokenHealthSection(health: health, onRefresh: {
                                Task { await viewModel.refresh() }
                            })
                            StyledDivider()
                        } else {
                            PopoverIdleFilteredView(
                                idleSessionMinutes: UserDefaults.standard.double(forKey: UserDefaultsKeys.idleSessionMinutes)
                            )
                            StyledDivider()
                        }
                    }
                }
                .animation(MotionConstants.snappy, value: metricModeRaw)

                if panelHasAppeared {
                    ProjectUsageGate(snapshot: snapshot)
                    InsightsGate(snapshot: snapshot)
                }

            } else if !showSettings && viewModel.isLoading {
                // First load — show minimal loading state
                HStack {
                    Spacer()
                    Text("Fetching usage data…")
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: Layout.spinnerSize, height: Layout.spinnerSize)
                    Spacer()
                }
                .frame(height: Layout.stateHeightLoading)
            } else if !showSettings, let error = viewModel.errorMessage {
                PopoverErrorView(message: error) {
                    Task { await viewModel.refresh() }
                }
            } else if !showSettings {
                PopoverEmptyView()
            }

            StyledDivider()
            PopoverFooterView(
                systemStatus: viewModel.systemStatus,
                isLoading: viewModel.isLoading,
                lastFreshFetch: viewModel.lastFreshFetch,
                isShowingCachedData: viewModel.isShowingCachedData,
                rateLimitSource: viewModel.snapshot?.rateLimits != nil ? viewModel.snapshot?.rateLimitSource : nil,
                footerMessage: viewModel.errorMessage,
                showLogoutConfirm: $showLogoutConfirm,
                onLogout: {
                    logoutRevertTask?.cancel()
                    OAuthManager.shared.signOut()
                    showLogoutConfirm = false
                },
                onRequestLogout: {
                    showLogoutConfirm = true
                    logoutRevertTask?.cancel()
                    logoutRevertTask = Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        guard !Task.isCancelled else { return }
                        showLogoutConfirm = false
                    }
                }
            )
        }
        .frame(width: min(scaledWidth, Layout.popoverWidth * 1.3))
        .contentShape(Rectangle())
        .overlay {
            TutorialOverlay(hasData: viewModel.snapshot != nil)
        }
        .onAppear {
            recomputeOrderedModes()
            DispatchQueue.main.async {
                panelHasAppeared = true
            }
        }
        .onChange(of: metricModeRaw) { _ in recomputeOrderedModes() }
        .onChange(of: autoMetricMode) { _ in
            recomputeOrderedModes()
            if !autoMetricMode { viewModel.resetHysteresis() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .panelKeyPress)) { notification in
            guard let key = notification.object as? String else { return }
            handleKeyPress(key)
        }
        .onReceive(NotificationCenter.default.publisher(for: .panelDidDismiss)) { _ in
            resetTransientPopoverState()
        }
        .onDisappear {
            panelHasAppeared = false
            resetTransientPopoverState()
        }
    }

    private func resetTransientPopoverState() {
        // No animation — panel is already hidden, animated state changes
        // would leave stale frames that show as blank space on next open.
        showSettings = false
        showLogoutConfirm = false
        logoutRevertTask?.cancel()
    }

    private func recomputeOrderedModes() {
        cachedOrderedModes = [metricMode] + MetricMode.allCases.filter { $0 != metricMode }
    }

    private func handleKeyPress(_ key: String) {
        switch key {
        case "1":
            viewModel.resetHysteresis()
            withAnimation(MotionConstants.snappy) { metricModeRaw = MetricMode.fiveHour.rawValue }
        case "2":
            viewModel.resetHysteresis()
            withAnimation(MotionConstants.snappy) { metricModeRaw = MetricMode.sevenDay.rawValue }
        case "3":
            viewModel.resetHysteresis()
            withAnimation(MotionConstants.snappy) { metricModeRaw = MetricMode.contextHealth.rawValue }
        case "r":
            Task { await viewModel.refresh() }
        default:
            // Arrow keys handled by TokenHealthSection via its own notification observer
            break
        }
    }
}
