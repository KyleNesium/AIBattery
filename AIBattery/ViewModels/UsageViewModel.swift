import Foundation
import SwiftUI

@MainActor
public final class UsageViewModel: ObservableObject {
    @Published var snapshot: UsageSnapshot?
    @Published var systemStatus: ClaudeSystemStatus?
    @Published var isLoading = true
    @Published var errorMessage: String?
    /// Timestamp of the last successful fresh (non-cached) API fetch.
    @Published var lastFreshFetch: Date?
    /// Whether the most recent API result was served from cache.
    @Published var isShowingCachedData = false
    /// Available update from GitHub Releases (nil if up-to-date or not checked).
    @Published var availableUpdate: VersionChecker.UpdateInfo?

    private let aggregator = UsageAggregator()
    private var fileWatcher: FileWatcher?
    private var pollingTimer: Timer?
    private var apiResult: APIFetchResult?
    private var wakeObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?

    /// Adaptive polling state machine — delegates interval logic to a pure struct.
    private var adaptivePolling = AdaptivePollingState()

    public init() {
        ThemeColors.registerObserver()
        NetworkMonitor.shared.start()

        // Show local data immediately so the menu bar icon appears fast,
        // then fetch network data in the background.
        let aggregator = self.aggregator
        let localSnapshot = aggregator.aggregate(rateLimits: nil)
        if localSnapshot.totalMessages > 0 {
            snapshot = localSnapshot
            isLoading = false
        }

        setupFileWatcher()
        setupSleepWakeObservers()
        startPolling()
        Task { await refresh() }
    }

    public func refresh() async {
        let oauthManager = OAuthManager.shared

        // Skip network work when not authenticated — still aggregate local data.
        guard oauthManager.isAuthenticated else {
            let result = aggregator.aggregate(rateLimits: nil)
            if result.totalMessages > 0 { snapshot = result }
            isLoading = false
            return
        }

        // Skip network when offline — show local data with cached rate limits.
        guard NetworkMonitor.shared.isConnected else {
            let result = aggregator.aggregate(rateLimits: apiResult?.rateLimits)
            snapshot = result
            isLoading = false
            errorMessage = "No internet connection"
            return
        }

        let wasEmpty = snapshot == nil
        if wasEmpty { isLoading = true }

        let accountId = oauthManager.accountStore.activeAccountId
        let (api, status) = await fetchAPIData(oauthManager: oauthManager, accountId: accountId)

        apiResult = api
        systemStatus = status
        isShowingCachedData = api.isCached
        if !api.isCached { lastFreshFetch = api.fetchedAt }

        // If user switched accounts while fetching, discard stale results.
        guard accountId == oauthManager.accountStore.activeAccountId else { return }

        resolveAccountIdentity(oauthManager: oauthManager, accountId: accountId, api: api)

        let result = aggregator.aggregate(rateLimits: api.rateLimits)
        logCorruptionMetrics()
        updateAdaptivePolling(result)
        updateSnapshot(result, api: api)
        await handlePostFetchAlerts(api: api, status: status)
    }

    // MARK: - Refresh helpers

    private func fetchAPIData(
        oauthManager: OAuthManager,
        accountId: String?
    ) async -> (APIFetchResult, ClaudeSystemStatus) {
        let accessToken = await oauthManager.getAccessToken()

        async let fetchedStatus = StatusChecker.shared.fetchStatus()

        let api: APIFetchResult
        if let token = accessToken, let id = accountId {
            api = await RateLimitFetcher.shared.fetch(accessToken: token, accountId: id)
        } else {
            api = APIFetchResult(rateLimits: nil, profile: nil)
        }

        return (api, await fetchedStatus)
    }

    private func resolveAccountIdentity(
        oauthManager: OAuthManager,
        accountId: String?,
        api: APIFetchResult
    ) {
        guard let id = accountId else { return }

        if let orgId = api.profile?.organizationId {
            let account = oauthManager.accountStore.accounts.first { $0.id == id }
            if account?.isPendingIdentity == true {
                oauthManager.resolveAccountIdentity(tempId: id, realOrgId: orgId)
            }
        }

        // Detect stale pending accounts — identity should resolve within the first fetch cycle.
        let account = oauthManager.accountStore.accounts.first { $0.id == id }
        if let account, account.isPendingIdentity,
           Date().timeIntervalSince(account.addedAt) > 3600 {
            errorMessage = "Account identity could not be confirmed. Try removing and re-adding this account."
        }
    }

    private func logCorruptionMetrics() {
        let corruptLines = SessionLogReader.shared.lastCorruptLineCount
        if corruptLines > 0 {
            AppLogger.files.warning("JSONL corruption: \(corruptLines) lines skipped or failed to decode")
        }
    }

    private func updateSnapshot(_ result: UsageSnapshot, api: APIFetchResult) {
        if api.rateLimits == nil && api.profile == nil {
            if result.totalMessages == 0 {
                errorMessage = "No usage data yet. Start a Claude Code session to see your stats."
            } else {
                errorMessage = "Unable to reach Anthropic API. Check your internet connection and try again."
            }
        } else {
            errorMessage = nil
        }

        snapshot = result
        isLoading = false
    }

    private func updateAdaptivePolling(_ result: UsageSnapshot) {
        let previousTotal = snapshot?.totalMessages ?? -1
        let previousToday = snapshot?.todayMessages ?? -1
        let dataChanged = previousTotal < 0
            || result.totalMessages != previousTotal
            || result.todayMessages != previousToday

        let interval = adaptivePolling.evaluate(
            dataChanged: dataChanged,
            baseInterval: refreshInterval
        )
        restartPolling(interval: interval)
    }

    private func handlePostFetchAlerts(api: APIFetchResult, status: ClaudeSystemStatus) async {
        NotificationManager.shared.checkStatusAlerts(status: status)

        if let limits = api.rateLimits {
            NotificationManager.shared.checkRateLimitAlerts(rateLimits: limits)
        }

        if availableUpdate == nil {
            availableUpdate = await VersionChecker.shared.checkForUpdate()
        }
    }

    /// Switch to a different account and refresh data.
    func switchAccount(to accountId: String) {
        OAuthManager.shared.accountStore.setActive(id: accountId)
        snapshot = nil
        isShowingCachedData = false
        lastFreshFetch = nil
        errorMessage = nil
        OAuthManager.shared.objectWillChange.send()
        Task { await refresh() }
    }

    // MARK: - Menu bar

    /// The currently selected metric mode, stored in UserDefaults.
    var metricMode: MetricMode {
        let raw = UserDefaults.standard.string(forKey: UserDefaultsKeys.metricMode) ?? "5h"
        return MetricMode(rawValue: raw) ?? .fiveHour
    }

    /// Percentage for the menu bar, driven by the selected metric mode.
    var menuBarPercent: Double {
        snapshot?.percent(for: metricMode) ?? 0
    }

    var hasData: Bool { snapshot != nil }

    // MARK: - Private

    private func setupFileWatcher() {
        fileWatcher = FileWatcher { [weak self] in
            Task { @MainActor [weak self] in
                self?.adaptivePolling.unchangedCycles = 0
                self?.restartPolling(interval: self?.refreshInterval ?? 60)
                await self?.refresh()
            }
        }
        fileWatcher?.startWatching()
    }

    /// Pause polling before sleep — avoids wasted timer fires while the
    /// system is suspended and ensures a clean lifecycle.
    /// On wake, reset adaptive polling and refresh immediately.
    private func setupSleepWakeObservers() {
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollingTimer?.invalidate()
                self?.pollingTimer = nil
            }
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.adaptivePolling.unchangedCycles = 0
                self?.restartPolling(interval: self?.refreshInterval ?? 60)
                await self?.refresh()
            }
        }
    }

    private var refreshInterval: TimeInterval {
        let stored = UserDefaults.standard.double(forKey: UserDefaultsKeys.refreshInterval)
        let interval = stored > 0 ? stored : 60
        return min(max(interval, 10), 60)
    }

    private func startPolling() {
        restartPolling(interval: refreshInterval)
    }

    /// Restart the polling timer with the given interval.
    private func restartPolling(interval: TimeInterval) {
        pollingTimer?.invalidate()
        let clamped = min(max(interval, 10), AdaptivePollingState.maxPollingInterval)
        pollingTimer = Timer.scheduledTimer(withTimeInterval: clamped, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
        pollingTimer?.tolerance = clamped * 0.1
    }

    func updatePollingInterval(_ interval: TimeInterval) {
        adaptivePolling.unchangedCycles = 0
        restartPolling(interval: interval)
    }

    deinit {
        pollingTimer?.invalidate()
        fileWatcher?.stopWatching()
        for observer in [wakeObserver, sleepObserver].compactMap({ $0 }) {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}
