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

    private let aggregator = UsageAggregator()
    private var fileWatcher: FileWatcher?
    private var pollingTimer: Timer?
    private var apiResult: APIFetchResult?

    public init() {
        // Show local data immediately so the menu bar icon appears fast,
        // then fetch network data in the background.
        let aggregator = self.aggregator
        let localSnapshot = aggregator.aggregate(rateLimits: nil, orgName: nil)
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

        // Resolve pending account identity from API response
        if let id = accountId, let orgId = api.profile?.organizationId {
            let account = oauthManager.accountStore.accounts.first { $0.id == id }
            if account?.isPendingIdentity == true {
                oauthManager.resolveAccountIdentity(
                    tempId: id,
                    realOrgId: orgId,
                    orgName: api.profile?.organizationName
                )
            } else {
                // Update metadata even for resolved accounts (org name may change)
                oauthManager.updateAccountMetadata(
                    accountId: id,
                    orgName: api.profile?.organizationName
                )
            }
        }

        // Guard: if user switched accounts while we were fetching, discard stale results.
        // The new account's refresh() is already in flight from switchAccount().
        let currentActiveId = oauthManager.accountStore.activeAccountId
        guard accountId == currentActiveId else { return }

        // Use account record for org name (multi-account) instead of UserDefaults
        let activeAccount = oauthManager.accountStore.activeAccount
        let orgName = api.profile?.organizationName ?? activeAccount?.organizationName

        // Aggregate on background thread — purely local, no timeout needed.
        let aggregator = self.aggregator
        let rateLimits = api.rateLimits
        let result = await Task.detached {
            aggregator.aggregate(rateLimits: rateLimits, orgName: orgName)
        }.value

        snapshot = result
        isLoading = false

        // Surface error if API returned no data at all (no cached result either)
        if api.rateLimits == nil && api.profile == nil && result.totalMessages == 0 {
            errorMessage = "Unable to reach Anthropic API. Check your internet connection and try again."
        } else {
            errorMessage = nil
        }

        // Check status page alerts for Claude.ai / Claude Code outages
        NotificationManager.shared.checkStatusAlerts(status: status)
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
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
    }

    func updatePollingInterval(_ interval: TimeInterval) {
        pollingTimer?.invalidate()
        let clamped = min(max(interval, 10), 60)
        pollingTimer = Timer.scheduledTimer(withTimeInterval: clamped, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
    }

    deinit {
        pollingTimer?.invalidate()
        fileWatcher?.stopWatching()
    }
}
