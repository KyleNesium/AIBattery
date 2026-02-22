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

    /// Adaptive polling: consecutive cycles with no data change.
    /// After 3 unchanged cycles, interval doubles (up to 5 min max).
    private var unchangedCycles = 0
    private static let adaptiveThreshold = 3
    private static let maxPollingInterval: TimeInterval = 300

    public init() {
        ThemeColors.registerObserver()

        // Show local data immediately so the menu bar icon appears fast,
        // then fetch network data in the background.
        let aggregator = self.aggregator
        let localSnapshot = aggregator.aggregate(rateLimits: nil)
        if localSnapshot.totalMessages > 0 {
            snapshot = localSnapshot
            isLoading = false
        }

        setupFileWatcher()
        startPolling()
        Task { await refresh() }
    }

    public func refresh() async {
        let wasEmpty = snapshot == nil
        if wasEmpty { isLoading = true }

        let oauthManager = OAuthManager.shared
        let accountId = oauthManager.accountStore.activeAccountId
        let accessToken = await oauthManager.getAccessToken()

        // Fetch API data and status concurrently — they hit different services.
        async let fetchedStatus = StatusChecker.shared.fetchStatus()

        let api: APIFetchResult
        if let token = accessToken, let id = accountId {
            api = await RateLimitFetcher.shared.fetch(accessToken: token, accountId: id)
        } else {
            api = APIFetchResult(rateLimits: nil, profile: nil)
        }

        let status = await fetchedStatus

        apiResult = api
        systemStatus = status

        // Track staleness
        isShowingCachedData = api.isCached
        if !api.isCached {
            lastFreshFetch = api.fetchedAt
        }

        // Guard: if user switched accounts while we were fetching, discard stale results.
        // The new account's refresh() is already in flight from switchAccount().
        let currentActiveId = oauthManager.accountStore.activeAccountId
        guard accountId == currentActiveId else { return }

        // Resolve pending account identity from API response
        if let id = accountId, let orgId = api.profile?.organizationId {
            let account = oauthManager.accountStore.accounts.first { $0.id == id }
            if account?.isPendingIdentity == true {
                oauthManager.resolveAccountIdentity(
                    tempId: id,
                    realOrgId: orgId
                )
            }
        }

        // Detect stale pending accounts — identity should resolve within the first fetch cycle.
        // If still pending after 1 hour, prompt user to re-authenticate.
        if let id = accountId {
            let account = oauthManager.accountStore.accounts.first { $0.id == id }
            if let account, account.isPendingIdentity,
               Date().timeIntervalSince(account.addedAt) > 3600 {
                errorMessage = "Account identity could not be confirmed. Try removing and re-adding this account."
            }
        }

        // Aggregate on background thread — purely local, no timeout needed.
        let aggregator = self.aggregator
        let rateLimits = api.rateLimits
        let result = await Task.detached {
            aggregator.aggregate(rateLimits: rateLimits)
        }.value

        // Log JSONL corruption metrics after aggregation
        let corruptLines = SessionLogReader.shared.lastCorruptLineCount
        if corruptLines > 0 {
            AppLogger.files.warning("JSONL corruption: \(corruptLines) lines skipped or failed to decode")
        }

        // Adaptive polling: compare key metrics to detect idle periods.
        let previousTotal = snapshot?.totalMessages ?? -1
        let previousToday = snapshot?.todayMessages ?? -1

        snapshot = result
        isLoading = false

        if result.totalMessages == previousTotal && result.todayMessages == previousToday
            && previousTotal >= 0 {
            unchangedCycles += 1
            if unchangedCycles >= Self.adaptiveThreshold {
                let extended = min(refreshInterval * 2, Self.maxPollingInterval)
                restartPolling(interval: extended)
            }
        } else {
            unchangedCycles = 0
            restartPolling(interval: refreshInterval)
        }

        // Surface error if API returned no data at all (no cached result either)
        if api.rateLimits == nil && api.profile == nil && result.totalMessages == 0 {
            errorMessage = "Unable to reach Anthropic API. Check your internet connection and try again."
        } else {
            errorMessage = nil
        }

        // Check status page alerts for Claude.ai / Claude Code outages
        NotificationManager.shared.checkStatusAlerts(status: status)

        // Check rate limit approaching alerts
        if let limits = api.rateLimits {
            NotificationManager.shared.checkRateLimitAlerts(rateLimits: limits)
        }

        // Check for app updates (rate-limited to once per 24h internally)
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
                self?.unchangedCycles = 0
                self?.restartPolling(interval: self?.refreshInterval ?? 60)
                await self?.refresh()
            }
        }
        fileWatcher?.startWatching()
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
        let clamped = min(max(interval, 10), Self.maxPollingInterval)
        pollingTimer = Timer.scheduledTimer(withTimeInterval: clamped, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
    }

    func updatePollingInterval(_ interval: TimeInterval) {
        unchangedCycles = 0
        restartPolling(interval: interval)
    }

    deinit {
        pollingTimer?.invalidate()
        fileWatcher?.stopWatching()
    }
}
