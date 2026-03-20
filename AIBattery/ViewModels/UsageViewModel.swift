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
    #if ENABLE_VERSION_CHECKER
    /// Available update from GitHub Releases (nil if up-to-date or not checked).
    @Published var availableUpdate: VersionChecker.UpdateInfo?
    #endif

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

        setupFileWatcher()
        setupSleepWakeObservers()

        // Show cached rate limits quickly — JSONL scan runs off main thread.
        let accountId = OAuthManager.shared.accountStore.activeAccountId
        if let accountId {
            let cached = RateLimitFetcher.shared.cachedOrEmpty(accountId: accountId)
            if cached.rateLimits != nil {
                let rl = cached.rateLimits
                Task { [weak self] in
                    guard let self else { return }
                    let result = await self.aggregator.aggregate(rateLimits: rl, accountId: accountId)
                    self.snapshot = result
                    self.isShowingCachedData = true
                    self.isLoading = false
                }
            }
        }

        // Start polling — first tick fires at the configured interval and does a full refresh.
        // Use a short initial delay (2s) so data appears quickly without blocking launch.
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
                self?.startPolling()
            }
        }
    }

    /// - Parameter skipNetworkCheck: When true, bypasses the offline guard. Used on wake
    ///   when NWPathMonitor may briefly report disconnected while WiFi reconnects.
    public func refresh(skipNetworkCheck: Bool = false) async {
        let oauthManager = OAuthManager.shared

        // Skip network work when not authenticated — still aggregate local data.
        guard oauthManager.isAuthenticated else {
            let result = await aggregator.aggregate(rateLimits: nil)
            if result.totalMessages > 0, result != snapshot { snapshot = result }
            isLoading = false
            return
        }

        // Skip network when offline — show local data with cached rate limits.
        guard skipNetworkCheck || NetworkMonitor.shared.isConnected else {
            let result = await aggregator.aggregate(rateLimits: apiResult?.rateLimits)
            if result != snapshot { snapshot = result }
            isLoading = false
            errorMessage = "No internet connection"
            return
        }

        let wasEmpty = snapshot == nil
        let accountId = oauthManager.accountStore.activeAccountId

        // Show cached rate limits immediately while API call is in-flight.
        // This eliminates the empty-bars delay on launch.
        if wasEmpty, let accountId {
            let cached = RateLimitFetcher.shared.cachedOrEmpty(accountId: accountId)
            if cached.rateLimits != nil {
                let earlyResult = await aggregator.aggregate(rateLimits: cached.rateLimits, accountId: accountId)
                snapshot = earlyResult
                isShowingCachedData = true
            } else {
                isLoading = true
            }
        }
        await Task.yield()

        let (api, status) = await fetchAPIData(oauthManager: oauthManager, accountId: accountId)

        apiResult = api
        systemStatus = status
        isShowingCachedData = api.isCached
        if !api.isCached { lastFreshFetch = api.fetchedAt }

        // If user switched accounts while fetching, discard stale results.
        guard accountId == oauthManager.accountStore.activeAccountId else { return }

        resolveAccountIdentity(oauthManager: oauthManager, accountId: accountId, api: api)
        Self.recordThrottleEvent(api.rateLimits)

        let result = await aggregator.aggregate(rateLimits: api.rateLimits, accountId: accountId)
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
        guard let account = oauthManager.accountStore.accounts.first(where: { $0.id == id }) else { return }

        if account.isPendingIdentity {
            if let orgId = api.profile?.organizationId {
                oauthManager.resolveAccountIdentity(tempId: id, realOrgId: orgId)
            } else if Date().timeIntervalSince(account.addedAt) > 3600 {
                errorMessage = "Account identity could not be confirmed. Try removing and re-adding this account."
            }
        }
    }

    private func logCorruptionMetrics() {
        let corruptLines = SessionLogReader.shared.lastCorruptLineCount
        if corruptLines > 0 {
            AppLogger.files.warning("JSONL corruption: \(corruptLines) lines skipped or failed to decode")
        }
    }

    private func updateSnapshot(_ result: UsageSnapshot, api: APIFetchResult) {
        errorMessage = Self.refreshErrorMessage(
            hasRateLimits: api.rateLimits != nil,
            hasProfile: api.profile != nil,
            totalMessages: result.totalMessages
        )
        if result != snapshot { snapshot = result }
        isLoading = false
    }

    private func updateAdaptivePolling(_ result: UsageSnapshot) {
        let dataChanged = Self.hasDataChanged(
            previousTotal: snapshot?.totalMessages ?? -1,
            previousToday: snapshot?.todayMessages ?? -1,
            newTotal: result.totalMessages,
            newToday: result.todayMessages
        )
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

        #if ENABLE_VERSION_CHECKER
        if availableUpdate == nil {
            availableUpdate = await VersionChecker.shared.checkForUpdate()
        }
        #endif
    }

    /// Switch to a different account and refresh data.
    func switchAccount(to accountId: String) {
        OAuthManager.shared.accountStore.setActive(id: accountId)
        snapshot = nil
        isShowingCachedData = false
        lastFreshFetch = nil
        errorMessage = nil
        isLoading = true
        OAuthManager.shared.objectWillChange.send()
        Task { await refresh() }
    }

    // MARK: - Private

    private func setupFileWatcher() {
        fileWatcher = FileWatcher { [weak self] in
            Task { @MainActor [weak self] in
                self?.aggregator.invalidate()
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
                guard let self else { return }
                // Show cached rate limits immediately so bars appear on wake
                // without waiting for the API round-trip.
                let accountId = OAuthManager.shared.accountStore.activeAccountId
                if let accountId {
                    let cached = RateLimitFetcher.shared.cachedOrEmpty(accountId: accountId)
                    if cached.rateLimits != nil {
                        let result = await self.aggregator.aggregate(rateLimits: cached.rateLimits, accountId: accountId)
                        if result != self.snapshot { self.snapshot = result }
                        self.isShowingCachedData = true
                    }
                }

                self.adaptivePolling.unchangedCycles = 0
                self.restartPolling(interval: self.refreshInterval)

                // Wait for WiFi to reconnect after sleep before hitting the API.
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                // Skip network check — NWPathMonitor may still report disconnected
                // while WiFi is reconnecting. Let the API call try and timeout naturally.
                await self.refresh(skipNetworkCheck: true)
            }
        }
    }

    private var refreshInterval: TimeInterval {
        Self.clampedRefreshInterval(UserDefaults.standard.double(forKey: UserDefaultsKeys.refreshInterval))
    }

    // MARK: - Testable static helpers

    /// Clamp a stored refresh interval to the valid range [10, 60]. Zero/negative → 60 (default).
    nonisolated static func clampedRefreshInterval(_ stored: Double) -> TimeInterval {
        let interval = stored > 0 ? stored : 60
        return min(max(interval, 10), 60)
    }

    /// Determine the error message to show after a refresh where the API returned no data.
    /// Returns nil when the API did return data (no error to show).
    nonisolated static func refreshErrorMessage(hasRateLimits: Bool, hasProfile: Bool, totalMessages: Int) -> String? {
        guard !hasRateLimits && !hasProfile else { return nil }
        if totalMessages == 0 {
            return "No usage data yet. Start a Claude Code session to see your stats."
        }
        return "Unable to reach Anthropic API. Check your internet connection and try again."
    }

    /// Whether snapshot data has changed compared to previous values. Used by adaptive polling.
    /// Returns true on first load (previousTotal < 0) or when totals differ.
    nonisolated static func hasDataChanged(previousTotal: Int, previousToday: Int, newTotal: Int, newToday: Int) -> Bool {
        previousTotal < 0 || newTotal != previousTotal || newToday != previousToday
    }

    /// Throttle transition tracker — pure struct, side-effects handled here.
    private static var throttleTracker = ThrottleTracker()

    /// Record a throttle event on the transition from normal → throttled/exhausted.
    /// Each distinct throttle session counts as one event regardless of duration.
    static func recordThrottleEvent(_ rateLimits: RateLimitUsage?) {
        let (next, timestamp) = throttleTracker.evaluate(rateLimits)
        throttleTracker = next
        if let timestamp {
            let existing = ThrottleTracker.parseTimestamps(
                UserDefaults.standard.array(forKey: UserDefaultsKeys.throttleTimestamps)
            )
            let updated = ThrottleTracker.appendAndPrune(timestamps: existing, newTimestamp: timestamp)
            UserDefaults.standard.set(updated, forKey: UserDefaultsKeys.throttleTimestamps)
        }
    }

    /// Count throttle events within a given number of days.
    static func throttleCount(days: Int) -> Int {
        let timestamps = ThrottleTracker.parseTimestamps(
            UserDefaults.standard.array(forKey: UserDefaultsKeys.throttleTimestamps)
        )
        return ThrottleTracker.count(timestamps: timestamps, days: days)
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
        // FileWatcher.deinit handles its own cleanup (cancels sources, streams, timers)
        for observer in [wakeObserver, sleepObserver].compactMap({ $0 }) {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}
