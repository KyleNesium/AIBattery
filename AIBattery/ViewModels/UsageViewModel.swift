import Foundation
import SwiftUI
import Combine

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
    /// The hysteresis-filtered metric mode for auto mode consumers.
    @Published private(set) var resolvedMetricMode: MetricMode = .fiveHour
    /// Per-account rate limits for the multi-account menu bar display.
    /// Keyed by account ID; only populated when `showAllAccountsInMenuBar` is on.
    @Published var perAccountRateLimits: [String: RateLimitUsage] = [:]

    #if ENABLE_VERSION_CHECKER
    /// Available update from GitHub Releases (nil if up-to-date or not checked).
    @Published var availableUpdate: VersionChecker.UpdateInfo?
    #endif

    /// Cross-poll hysteresis state — the mode displayed on the previous poll.
    /// Reset on manual mode override and account switch.
    private var lastResolvedMode: MetricMode?

    // Stored state that the lifecycle / fan-out extensions also touch is
    // declared without `private` so it remains visible across the extension
    // files in the same module. `aggregator`, `fileWatcher`, `pollingTimer`,
    // and the sleep/wake observers are read or written by
    // `UsageViewModel+Lifecycle.swift`; nothing else in the module touches them.
    let aggregator = UsageAggregator()
    /// Serializes concurrent aggregateOffMain calls — only one detached task runs at a time.
    private var inflightAggregation: Task<(UsageSnapshot, UsageAggregator.SideEffects), Never>?
    var fileWatcher: FileWatcher?
    var pollingTimer: Timer?
    private var apiResult: APIFetchResult?
    var wakeObserver: NSObjectProtocol?
    var sleepObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    /// Coalesces UserDefaults change notifications into a single fan-out.
    /// Read/written by `UsageViewModel+FanOut.swift`.
    var pendingFanOut: Task<Void, Never>?
    /// Last observed value of the multi-account toggle — used to filter the
    /// `UserDefaults.didChangeNotification` firehose down to actual toggle flips.
    private var lastObservedShowAllAccounts: Bool = UserDefaults.standard.bool(forKey: UserDefaultsKeys.showAllAccountsInMenuBar)

    /// Adaptive polling state machine — delegates interval logic to a pure struct.
    /// Read/written by lifecycle extension (`updatePollingInterval`, `resumeTimers`).
    var adaptivePolling = AdaptivePollingState()

    /// Timestamp of the last API response that included fresh (non-nil) rate limits.
    /// Used to expire stale fallback data — after `rateLimitStaleTTL` seconds without
    /// fresh data, the fallback is dropped so the UI transitions to StandardRateLimits.
    private var lastFreshRateLimitsAt: Date?

    /// How long stale rate limits are carried forward before expiring (seconds).
    /// 5 minutes handles transient network failures (1-2 poll cycles) without
    /// showing frozen percentages indefinitely when unified headers are gone.
    /// Keep the last good API rate limit data until replaced by a newer API response.
    /// The unified headers arrive intermittently (~10% of polls) — expiring them
    /// causes the UI to flip between API data and local estimates.
    /// 24 hours ensures we hold through overnight sleep cycles.
    static let rateLimitStaleTTL: TimeInterval = 86_400

    /// Short delay before the first API poll so data appears quickly without blocking launch.
    private static let initialPollDelay: TimeInterval = 2

    /// True when timers are suspended due to system idle or screen lock.
    /// Read/written by lifecycle extension; tests assert suspend/resume cycle.
    var isSuspended = false
    var lockObserver: NSObjectProtocol?
    var unlockObserver: NSObjectProtocol?
    /// Global event monitor that detects user activity (mouse/keyboard) to resume
    /// from idle suspension. Only active while suspended — removed on resume.
    /// Internal for testing — tests verify suspend/resume toggles this.
    var activityMonitor: Any?

    public init() {
        LocalUsageEstimate.migrateIfNeeded()
        ThemeColors.registerObserver()
        NetworkMonitor.shared.start()

        setupFileWatcher()
        setupSleepWakeObservers()

        // Show cached rate limits quickly — JSONL scan runs off main thread.
        let accountId = OAuthManager.shared.accountStore.activeAccountId
        if let accountId {
            let cached = RateLimitFetcher.shared.cachedOrEmpty(accountId: accountId)
            if cached.rateLimits != nil || cached.standardLimits != nil {
                // Persisted rate limits from last session — treat as still-valid
                // so the stale TTL keeps them alive until a fresh API response.
                if cached.rateLimits != nil {
                    lastFreshRateLimitsAt = cached.fetchedAt
                }
                Task { [weak self] in
                    guard let self else { return }
                    let result = await self.aggregateOffMain(
                        rateLimits: cached.rateLimits,
                        rateLimitSource: cached.rateLimitSource,
                        standardLimits: cached.standardLimits,
                        accountId: accountId
                    )
                    self.snapshot = result
                    self.isShowingCachedData = true
                    self.isLoading = false
                }
            }
        }

        // Start polling — first tick fires at the configured interval and does a full refresh.
        pollingTimer = Timer.scheduledTimer(withTimeInterval: Self.initialPollDelay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
                self?.startPolling()
            }
        }

        // Toggle observer: the "Show all accounts in menu bar" preference doesn't
        // emit a Combine signal on its own (UserDefaults / @AppStorage writes don't),
        // so we watch `UserDefaults.didChangeNotification` and react only when the
        // toggle key actually changed. Filtering here matters: the notification fires
        // on every UserDefaults write (slider drags, every other @AppStorage), and
        // each spurious fan-out triggers (N-1) API calls when the toggle is on.
        NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let current = UserDefaults.standard.bool(forKey: UserDefaultsKeys.showAllAccountsInMenuBar)
                guard current != self.lastObservedShowAllAccounts else { return }
                self.lastObservedShowAllAccounts = current
                self.scheduleFanOut()
            }
            .store(in: &cancellables)
    }

    /// Run aggregate off the main thread, then apply @MainActor side effects.
    /// Best-effort serialization: waits for any in-flight aggregation before starting
    /// a new one. UsageAggregator's internal lock is the primary guard against concurrent
    /// mutation; this layer reduces redundant overlapping work.
    func aggregateOffMain(
        rateLimits: RateLimitUsage?,
        rateLimitSource: RateLimitSource? = nil,
        standardLimits: StandardRateLimits? = nil,
        accountId: String? = nil
    ) async -> UsageSnapshot {
        if let inflight = inflightAggregation {
            _ = await inflight.value
        }

        let agg = aggregator
        let task = Task.detached {
            agg.aggregate(rateLimits: rateLimits, rateLimitSource: rateLimitSource, standardLimits: standardLimits, accountId: accountId)
        }
        inflightAggregation = task
        let (result, effects) = await task.value

        // Apply side effects before clearing inflightAggregation so the next
        // caller sees consistent RateLimitFetcher state.
        RateLimitFetcher.shared.activeUserModel = effects.activeUserModel
        if let id = effects.accountId {
            RateLimitFetcher.shared.setObservedModels(effects.observedModels, accountId: id)
        }
        inflightAggregation = nil
        return result
    }

    /// - Parameter skipNetworkCheck: When true, bypasses the offline guard. Used on wake
    ///   when NWPathMonitor may briefly report disconnected while WiFi reconnects.

    public func refresh(skipNetworkCheck: Bool = false) async {
        // Skip polling cycle when suspended due to idle or screen lock.
        // Allow explicit resume refreshes through by checking skipNetworkCheck (wake path).
        guard !isSuspended || skipNetworkCheck else { return }

        // Check idle at each polling tick — suspend if threshold reached.
        // No new timer — piggybacks on the existing polling cycle.
        if !skipNetworkCheck {
            let idle = IdleSuspendPolicy.idleSeconds()
            if IdleSuspendPolicy.shouldSuspend(secondsIdle: idle) {
                suspendTimers()
                return
            }
        }

        let oauthManager = OAuthManager.shared

        // Skip network work when not authenticated — still aggregate local data.
        guard oauthManager.isAuthenticated else {
            let result = await aggregateOffMain(rateLimits: nil)
            if result.totalMessages > 0, result != snapshot { snapshot = result }
            isLoading = false
            return
        }

        // Skip network when offline — show local data with cached rate limits.
        guard skipNetworkCheck || NetworkMonitor.shared.isConnected else {
            let result = await aggregateOffMain(
                rateLimits: apiResult?.rateLimits,
                rateLimitSource: apiResult?.rateLimitSource,
                standardLimits: apiResult?.standardLimits
            )
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
            if cached.rateLimits != nil || cached.standardLimits != nil {
                let earlyResult = await aggregateOffMain(
                    rateLimits: cached.rateLimits,
                    rateLimitSource: cached.rateLimitSource,
                    standardLimits: cached.standardLimits,
                    accountId: accountId
                )
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
        // Hold the last good API rate limit data until replaced by a newer API response.
        // With only ~10% of polls returning unified headers, expiring quickly causes
        // the UI to flip between API data and local estimates. Stale API data (with
        // real utilization %) is always more useful than local token estimates.
        if api.rateLimits != nil && !api.isCached {
            lastFreshRateLimitsAt = Date()
        }
        let effectiveRateLimits = Self.effectiveRateLimits(
            fresh: api.rateLimits,
            stale: snapshot?.rateLimits,
            lastFreshAt: lastFreshRateLimitsAt,
            ttl: Self.rateLimitStaleTTL
        )
        let effectiveSource = Self.effectiveValue(
            fresh: api.rateLimitSource,
            stale: snapshot?.rateLimitSource,
            lastFreshAt: lastFreshRateLimitsAt,
            ttl: Self.rateLimitStaleTTL
        )
        let result = await aggregateOffMain(
            rateLimits: effectiveRateLimits,
            rateLimitSource: effectiveSource,
            standardLimits: api.standardLimits ?? snapshot?.standardLimits,
            accountId: accountId
        )
        logCorruptionMetrics()

        // Keep latest token counts available for 429 auto-calibration.
        LocalUsageEstimate.latestFiveHourTokens = result.fiveHourTokens
        LocalUsageEstimate.latestSevenDayTokens = result.sevenDayTokens

        // Auto-calibrate local usage limits when API returns fresh utilization data.
        // This lets us estimate percentages from local tokens when the API is unavailable.
        if let rl = api.rateLimits, !api.isCached {
            LocalUsageEstimate.calibrate(
                fiveHourUtilization: rl.fiveHourUtilization,
                sevenDayUtilization: rl.sevenDayUtilization,
                localFiveHourTokens: result.fiveHourTokens,
                localSevenDayTokens: result.sevenDayTokens
            )
        }

        updateAdaptivePolling(result)
        updateSnapshot(result, api: api)
        await handlePostFetchAlerts(api: api, status: status)
        // Multi-account menu bar fan-out (no-op when toggle is off).
        // Seed with the active account's just-fetched data — RateLimitFetcher does
        // not short-circuit on cache, so seeding is what keeps net cost at N
        // requests per cycle for N accounts (instead of N+1).
        let seed: (String, RateLimitUsage)? = {
            guard let id = accountId, let rl = api.rateLimits, !api.isCached else { return nil }
            return (id, rl)
        }()
        await fetchAllAccounts(seed: seed)
    }

    // MARK: - Refresh helpers

    private func fetchAPIData(
        oauthManager: OAuthManager,
        accountId: String?
    ) async -> (APIFetchResult, ClaudeSystemStatus) {
        let accessToken = await oauthManager.getAccessToken()

        async let fetchedStatus = StatusChecker.shared.fetchStatus()

        let api: APIFetchResult = if let token = accessToken, let id = accountId {
            await RateLimitFetcher.shared.fetch(accessToken: token, accountId: id)
        } else {
            APIFetchResult(rateLimits: nil, profile: nil)
        }

        return await (api, fetchedStatus)
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
            } else if Date().timeIntervalSince(account.addedAt) > 3_600 {
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
            hasStandardLimits: api.standardLimits != nil,
            hasProfile: api.profile != nil,
            hasStandardRateLimitHeaders: api.hasStandardRateLimitHeaders,
            totalMessages: result.totalMessages,
            authError: api.authError
        )
        if result != snapshot { snapshot = result }

        // Apply hysteresis to auto-resolved mode
        let candidate = result.autoResolvedMode
        let filtered = UsageSnapshot.applyHysteresis(
            candidate: candidate,
            previous: lastResolvedMode,
            snapshot: result
        )
        lastResolvedMode = filtered
        resolvedMetricMode = filtered

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

    /// Reset hysteresis state — called when user manually selects a mode or switches accounts.
    func resetHysteresis() {
        lastResolvedMode = nil
    }

    /// Switch to a different account and refresh data.
    func switchAccount(to accountId: String) {
        OAuthManager.shared.accountStore.setActive(id: accountId)
        lastResolvedMode = nil
        snapshot = nil
        isShowingCachedData = false
        lastFreshFetch = nil
        errorMessage = nil
        isLoading = true
        OAuthManager.shared.objectWillChange.send()
        Task { await refresh() } // refresh() also calls fetchAllAccounts() at its tail.
    }

    // MARK: - Throttle bookkeeping
    //
    // Static helpers that are pure / stateless live in `UsageViewModel+Statics.swift`.
    // The throttle tracker stays here because it depends on a stored static
    // ThrottleTracker (`throttleTracker`), which only makes sense alongside
    // the storage it manages.

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

    deinit {
        pollingTimer?.invalidate()
        if let monitor = activityMonitor { NSEvent.removeMonitor(monitor) }
        // FileWatcher.deinit handles its own cleanup (cancels sources, streams, timers)
        for observer in [wakeObserver, sleepObserver, lockObserver, unlockObserver].compactMap({ $0 }) {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}
