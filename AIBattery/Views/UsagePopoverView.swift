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
    /// Overview (all accounts) vs detail (the active account). Decided on every
    /// panel open from the eligible account count; never remembered across opens.
    @State private var mode: PopoverMode = .detail
    @AppStorage(UserDefaultsKeys.showFullAccountIdentity) private var showFullAccountIdentity: Bool = false
    @State private var addingProvider: AIProvider?
    @AppStorage(UserDefaultsKeys.metricMode) private var metricModeRaw: String = "5h"
    @AppStorage(UserDefaultsKeys.autoMetricMode) private var autoMetricMode: Bool = false
    @State private var accountCountAtAddStart = 0
    @State private var showLogoutConfirm = false
    @State private var logoutRevertTask: Task<Void, Never>?
    /// Gates the heavy sections (Projects/Insights incl. Swift Charts). Armed one
    /// run-loop after `.panelDidShow` (every real open) so the core bars paint first;
    /// DISARMED on panel dismiss so a hidden panel stops re-rendering them on every
    /// @Published change (`orderOut` keeps the hosting view in the hierarchy — without
    /// the dismiss reset, the full tree re-evaluated invisibly on every poll, burning
    /// CPU). Never armed by `onAppear` — that fires at setup, not on show.
    @State private var deferredRender = DeferredRenderState()

    /// Cached ordered modes — avoids allocating a new array on every body evaluation.
    @State private var cachedOrderedModes: [MetricMode] = MetricMode.allCases
    private var orderedModes: [MetricMode] { cachedOrderedModes }

    /// Shape of the active account's quota (windows / credits / per-minute API limits).
    private func displayKind(_ snapshot: UsageSnapshot) -> CodexDisplayKind {
        guard snapshot.provider == .codex else { return .windows }
        return CodexDisplayKind.of(
            rateLimits: snapshot.rateLimits,
            standardLimits: snapshot.standardLimits,
            apiKeyAccount: accountStore.activeAccount?.isAPIKeyAccount ?? false
        )
    }

    /// Set by the panel so Escape can step back to the overview instead of closing.
    private let registerEscapeHandler: ((@escaping () -> Bool) -> Void)?

    public init(viewModel: UsageViewModel, registerEscapeHandler: ((@escaping () -> Bool) -> Void)? = nil) {
        self.viewModel = viewModel
        self.accountStore = OAuthManager.shared.accountStore
        self.registerEscapeHandler = registerEscapeHandler
    }

    private var localEstimateHeaderText: String {
        if LocalUsageEstimate.isCalibrated() {
            return "Estimated from local data"
        }
        if PlanTier.effective(forAccountId: AccountStore.persistedActiveAccountId) != nil {
            return "Estimated from plan tier"
        }
        return "Local token usage"
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
        // The lifecycle modifiers live out here, ABOVE the face switch. Hanging them on
        // one face meant switching faces unmounted that face and fired its `onDisappear`
        // — which resets transient state, including the face itself, so the overview
        // flipped straight back to detail and the back control appeared to do nothing.
        faces
            .onAppear {
                registerEscape()
                // No deferredRender.appeared() here: onAppear fires when the hosting view
                // is attached at setup (launch), NOT on panel show — arming here would race
                // the launch pre-warm's orderOut and could leave the heavy sections armed
                // on a never-opened panel. Every real open posts .panelDidShow instead.
                recomputeOrderedModes()
            }
            .onChange(of: metricModeRaw) { _ in recomputeOrderedModes() }
            .onChange(of: autoMetricMode) { _ in
                recomputeOrderedModes()
                if !autoMetricMode {
                    viewModel.resetHysteresis()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .panelKeyPress)) { notification in
                guard let key = notification.object as? String else { return }
                if mode == .overview {
                    handleOverviewKeyPress(key)
                } else {
                    handleKeyPress(key)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .panelDidShow)) { _ in
                // Every open re-decides the face: two or more accounts land on the overview.
                mode = PopoverMode.initial(eligibleAccountCount: eligibleAccountCount)
                // Deferred one run-loop (mirrors onAppear): the re-opened panel paints
                // the core bars first, then the heavy sections fill in. The overview has
                // no heavy sections, so only the detail face arms them.
                guard mode == .detail else { return }
                DispatchQueue.main.async {
                    deferredRender.appeared()
                }
            }
            .onReceive(accountStore.$accounts) { accounts in
                // Signing out of the second-to-last account leaves the overview with nothing
                // to compare; gaining one never yanks the user out of a detail view.
                mode = PopoverMode.next(current: mode, eligibleAccountCount: AccountCard.eligibleCount(accounts: accounts))
            }
            .onReceive(NotificationCenter.default.publisher(for: .panelDidDismiss)) { _ in
                resetTransientPopoverState()
            }
            .onDisappear {
                resetTransientPopoverState()
            }
    }

    @ViewBuilder
    private var faces: some View {
        if let addingProvider {
            AuthView(
                oauthManager: OAuthManager.shared,
                provider: addingProvider,
                isAddingAccount: true,
                onCancel: {
                    // Dismissing the overlay must also stop a browser sign-in that is
                    // still waiting on the callback port, or the pending exchange could
                    // register an account (and write its Keychain item) after "Cancel".
                    OAuthManager.shared.cancelCodexAuthFlow()
                    self.addingProvider = nil
                }
            )
            .onAppear { accountCountAtAddStart = accountStore.accounts.count }
            .onReceive(accountStore.$accounts) { newAccounts in
                // Auth completed for new account — detect actual addition, not initial publish
                if newAccounts.count > accountCountAtAddStart && self.addingProvider != nil {
                    self.addingProvider = nil
                    // The add path already made the new account active via `setActive`, which
                    // bypasses `switchAccount` — a bare `refresh()` would leave the previous
                    // account's snapshot in place and serve its limits as the stale fallback.
                    viewModel.syncToActiveAccount()
                }
            }
        } else if mode == .overview {
            overviewContent
        } else {
            mainContent
        }
    }

    /// Accounts the overview lists (identity resolved; signed-out ones become sign-in
    /// cards) — also the count the mode is decided from.
    private var eligibleAccountCount: Int {
        AccountCard.eligibleCount(accounts: accountStore.accounts)
    }

    private var overviewCards: [AccountCard] {
        AccountCard.rows(
            accounts: accountStore.accounts,
            activeId: accountStore.activeAccountId,
            readings: viewModel.perAccountReadings,
            statuses: viewModel.providerStatuses,
            snapshots: viewModel.providerSnapshots,
            isAuthenticated: { OAuthManager.shared.isAuthenticated(accountId: $0) },
            maskEmail: !showFullAccountIdentity,
            now: Date()
        )
    }

    /// An update that was found and whose banner was dismissed badges the gear, wherever
    /// the gear happens to live. `VersionChecker` is compiled out in some configurations.
    private var gearShowsUpdateBadge: Bool {
        #if ENABLE_VERSION_CHECKER
        return viewModel.availableUpdate != nil
        #else
        return false
        #endif
    }

    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showSettings {
                // Settings replaces the cards, exactly as it replaces the detail sections.
                // The footer's gear stays put, so the same control closes it again.
                SettingsRow(
                    viewModel: viewModel,
                    accountStore: accountStore,
                    onAddAccount: { addingProvider = $0 }
                )
                .transition(.opacity)
            } else {
                OverviewContentView(
                    cards: overviewCards,
                    canAddClaude: accountStore.canAddAccount(provider: .claude),
                    canAddCodex: accountStore.canAddAccount(provider: .codex),
                    onSelect: { select($0) },
                    onAdd: { addingProvider = $0 }
                )
                .transition(.opacity)
            }
            StyledDivider()
            // The detail footer's links are all about ONE account; the overview gets its
            // own with what applies to every account — and the gear, because the overview
            // has no header to hold it.
            OverviewFooterView(
                lastFreshFetch: viewModel.lastFreshFetch,
                isLoading: viewModel.isLoading,
                showsUpdateBadge: gearShowsUpdateBadge,
                showSettings: $showSettings,
                onRefresh: {
                    viewModel.scheduleFanOut()
                    Task { await viewModel.refresh() }
                }
            )
        }
        .frame(width: min(scaledWidth, Layout.popoverWidth * 1.3))
        .contentShape(Rectangle())
    }

    /// Open one account's detail view. A signed-out card starts its sign-in instead.
    private func select(_ card: AccountCard) {
        if card.state == .signedOut {
            addingProvider = card.provider
            return
        }
        withAnimation(MotionConstants.standard) {
            if card.id != accountStore.activeAccountId {
                viewModel.switchAccount(to: card.id)
            }
            mode = .detail
        }
        // Mirror the panel-show path: let the core bars paint before the heavy sections.
        DispatchQueue.main.async { deferredRender.appeared() }
    }

    /// In the overview, digits pick a card and `r` refreshes every account.
    private func handleOverviewKeyPress(_ key: String) {
        if key == "r" {
            viewModel.scheduleFanOut()
            Task { await viewModel.refresh() }
            return
        }
        guard let index = Int(key), index >= 1 else { return }
        let cards = overviewCards
        guard index <= cards.count else { return }
        select(cards[index - 1])
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            PopoverHeaderView(
                accountStore: accountStore,
                showSettings: $showSettings,
                onAddAccount: { addingProvider = $0 },
                onSwitchAccount: { accountId in
                    viewModel.switchAccount(to: accountId)
                },
                availableUpdate: viewModel.availableUpdate,
                showsBack: PopoverHeaderView.showsBack(eligibleAccountCount: eligibleAccountCount),
                onBack: { withAnimation(MotionConstants.standard) { mode = .overview } }
            )

            if showSettings {
                SettingsRow(
                    viewModel: viewModel,
                    accountStore: accountStore,
                    onAddAccount: { addingProvider = $0 }
                )
                .transition(.opacity)
                // No StyledDivider here — the always-present divider above the footer
                // already separates the settings stack from the footer row. Adding
                // another here renders a doubled-up line at the bottom.
            } else if let snapshot = viewModel.snapshot {
                MetricToggleView(
                    pickerBinding: pickerBinding,
                    snapshot: snapshot,
                    provider: snapshot.provider,
                    kind: displayKind(snapshot)
                )

                // Local estimate header — shown once when API rate limits are unavailable
                if snapshot.rateLimits == nil && snapshot.isUsingLocalEstimate {
                    HStack(spacing: Spacing.inner) {
                        Text(localEstimateHeaderText)
                            .font(Typography.tinyLabel)
                            .foregroundStyle(ThemeColors.secondaryLabel)
                        Button(action: {
                            if let url = URL(string: "https://github.com/KyleNesium/AIBattery/issues/141") {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            Image(systemName: "info.circle.fill")
                                .font(Typography.tinyLabel)
                                .foregroundStyle(ThemeColors.caution)
                        }
                        .buttonStyle(.plain)
                        .help("Anthropic removed usage headers from their API. Tap for details.")
                        .accessibilityLabel("Why usage is estimated locally")
                        .accessibilityHint("Opens an explanation in your browser")
                        Spacer()
                    }
                    .padding(.horizontal, Spacing.sectionHorizontal)
                    .padding(.top, Spacing.section)
                }

                // All 3 sections always render (selected mode first via orderedModes).
                ForEach(orderedModes, id: \.rawValue) { mode in
                    switch mode {
                    case .fiveHour:
                        if let limits = snapshot.rateLimits, limits.isCreditBudget, let budget = limits.creditBudget {
                            // Codex credit budget: one bar stands in for both windows.
                            CreditBudgetSection(limits: limits, budget: budget, source: snapshot.rateLimitSource, confirmed: snapshot.rateLimitPercentConfirmed(for: RateLimitUsage.sevenDayWindow))
                            StyledDivider()
                        } else if let limits = snapshot.rateLimits {
                            FiveHourBarSection(limits: limits, source: snapshot.rateLimitSource, tokenTotal: snapshot.fiveHourWindowTokens(resetsAt: limits.fiveHourReset), confirmed: snapshot.rateLimitPercentConfirmed(for: RateLimitUsage.fiveHourWindow))
                            StyledDivider()
                        } else if snapshot.isUsingLocalEstimate {
                            LocalEstimateSection(
                                fiveHourTokens: snapshot.fiveHourTokens,
                                sevenDayTokens: snapshot.sevenDayTokens,
                                window: .fiveHour,
                                provider: snapshot.provider
                            )
                            StyledDivider()
                        } else if let stdLimits = snapshot.standardLimits {
                            StandardLimitsSection(limits: stdLimits, provider: snapshot.provider)
                            StyledDivider()
                        } else if displayKind(snapshot) == .apiLimits {
                            // An API-key account selects the "API Limits" tab from the
                            // account type alone, but `standardLimits` is nil until the
                            // first `/v1/responses` probe lands. `.sevenDay` is EmptyView
                            // for this kind, so with no terminal branch here the user got
                            // a highlighted tab over blank space and no explanation.
                            AwaitingAPILimitsSection()
                            StyledDivider()
                        }
                    case .sevenDay:
                        if displayKind(snapshot) != .windows {
                            // Rendered once in the .fiveHour slot as the Credits / API Limits bar.
                            EmptyView()
                        } else if let limits = snapshot.rateLimits {
                            SevenDayBarSection(limits: limits, source: snapshot.rateLimitSource, tokenTotal: snapshot.sevenDayWindowTokens(resetsAt: limits.sevenDayReset), confirmed: snapshot.rateLimitPercentConfirmed(for: RateLimitUsage.sevenDayWindow))
                            if let balance = limits.creditBalance {
                                CreditBalanceRow(balance: balance, unlimited: limits.creditBudget?.unlimited ?? false)
                            }
                            StyledDivider()
                        } else if snapshot.isUsingLocalEstimate {
                            LocalEstimateSection(
                                fiveHourTokens: snapshot.fiveHourTokens,
                                sevenDayTokens: snapshot.sevenDayTokens,
                                window: .sevenDay,
                                provider: snapshot.provider
                            )
                            StyledDivider()
                        } else if let stdLimits = snapshot.standardLimits {
                            StandardLimitsSection(limits: stdLimits, provider: snapshot.provider)
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

                if deferredRender.hasAppeared {
                    ProjectUsageGate(snapshot: snapshot)
                    InsightsGate(snapshot: snapshot)
                }

            } else if !showSettings && viewModel.isLoading {
                // First load — show minimal loading state
                HStack {
                    Spacer()
                    Text("Fetching usage data…")
                        .font(Typography.caption)
                        .foregroundStyle(ThemeColors.secondaryLabel)
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
                PopoverEmptyView(provider: accountStore.activeAccount?.provider ?? .claude)
            }

            StyledDivider()
            footerView
        }
        .frame(width: min(scaledWidth, Layout.popoverWidth * 1.3))
        .contentShape(Rectangle())
        .overlay {
            TutorialOverlay(hasData: viewModel.snapshot != nil, kind: viewModel.snapshot.map(displayKind) ?? .windows)
        }
    }

    /// The popover's footer — identical on both faces (links and timestamp follow the
    /// active account).
    private var footerView: some View {
        PopoverFooterView(
            systemStatus: viewModel.systemStatus,
            provider: accountStore.activeAccount?.provider ?? .claude,
            apiKeyAccount: accountStore.activeAccount?.isAPIKeyAccount ?? false,
            isLoading: viewModel.isLoading,
            lastFreshFetch: viewModel.lastFreshFetch,
            isShowingCachedData: viewModel.isShowingCachedData,
            rateLimitSource: viewModel.snapshot?.rateLimits != nil ? viewModel.snapshot?.rateLimitSource : nil,
            footerMessage: viewModel.errorMessage,
            showLogoutConfirm: $showLogoutConfirm,
            onLogout: {
                logoutRevertTask?.cancel()
                OAuthManager.shared.signOut()
                // `remove` reassigns the active account to `accounts.first`; re-point the
                // view model so a remaining account never shows the removed one's bars.
                viewModel.syncToActiveAccount()
                showLogoutConfirm = false
            },
            onRequestLogout: {
                showLogoutConfirm = true
                logoutRevertTask?.cancel()
                logoutRevertTask = Task {
                    try? await Task.sleep(nanoseconds: MotionConstants.logoutConfirmNs)
                    guard !Task.isCancelled else { return }
                    showLogoutConfirm = false
                }
            }
        )
    }

    /// Escape steps back to the overview from a detail view that has one; everywhere
    /// else the panel closes. Registered once; it reads the current state each press.
    private func registerEscape() {
        guard let registerEscapeHandler else { return }
        registerEscapeHandler {
            let action = PopoverEscapeRouting.consume(
                mode: mode,
                showSettings: showSettings,
                showsBack: PopoverHeaderView.showsBack(eligibleAccountCount: eligibleAccountCount)
            )
            switch action {
            case .backToOverview:
                withAnimation(MotionConstants.standard) { mode = .overview }
                return true
            case .close:
                return false
            }
        }
    }

    private func resetTransientPopoverState() {
        // No animation — panel is already hidden, animated state changes
        // would leave stale frames that show as blank space on next open.
        showSettings = false
        showLogoutConfirm = false
        // Dismiss only (the panel is hidden): the next open recomputes the face from
        // the account count in the `.panelDidShow` handler.
        mode = .detail
        logoutRevertTask?.cancel()
        // Collapse the heavy sections while hidden — orderOut doesn't fire
        // onDisappear, so without this the hidden panel kept re-rendering
        // Projects/Insights (incl. Swift Charts) on every poll.
        deferredRender.disappeared()
    }

    private func recomputeOrderedModes() {
        cachedOrderedModes = MetricMode.orderedModes(current: metricMode)
    }

    private func handleKeyPress(_ key: String) {
        switch key {
        case "1":
            viewModel.resetHysteresis()
            withAnimation(MotionConstants.snappy) { metricModeRaw = MetricMode.fiveHour.rawValue }
        case "2":
            viewModel.resetHysteresis()
            // Single-budget kinds (Credits / API Limits) have no second window tab — "2"
            // selects the one budget tab instead of a hidden mode.
            let collapsed = viewModel.snapshot.map { displayKind($0) != .windows } ?? false
            let target: MetricMode = collapsed ? .fiveHour : .sevenDay
            withAnimation(MotionConstants.snappy) { metricModeRaw = target.rawValue }
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
