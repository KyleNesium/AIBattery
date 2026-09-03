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
    /// Whether the displayed rate-limit *values* came from a genuinely fresh fetch this
    /// cycle (unified headers AND not cache-served). Distinct from `!isShowingCachedData`:
    /// a fetch can succeed without unified headers (~90% of polls), reusing held stale
    /// rate limits — which must not arm the "Limit reached" alarm. Gates only the alarm
    /// (with `alarmConfirmed`); the displayed percentage is always the real API value.
    @Published var rateLimitsFresh = false
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
    // Polling timer + NSWorkspace observers: read/written from MainActor methods,
    // but the nonisolated `deinit` must invalidate/remove them. `nonisolated(unsafe)`
    // lets the deinit touch them; Timer.invalidate and NSWorkspace.removeObserver
    // are documented thread-safe.
    nonisolated(unsafe) var pollingTimer: Timer?
    /// One-shot timer armed for the next window reset so an exhausted bar rolls over to
    /// 0% the moment its countdown ends instead of showing a stale 100% until the next
    /// poll. Re-armed on every snapshot publish (see `scheduleRolloverClear`).
    nonisolated(unsafe) private var rolloverClearTimer: Timer?
    private var apiResult: APIFetchResult?
    nonisolated(unsafe) var wakeObserver: NSObjectProtocol?
    nonisolated(unsafe) var sleepObserver: NSObjectProtocol?
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

    /// Set by `refreshLocalData()` when a file-system re-aggregate changed the message
    /// totals between timed polls; consumed (and cleared) by `updateAdaptivePolling`.
    /// Without it, the FS path keeping `snapshot` current would make every timed poll
    /// compare equal totals → "unchanged" → polling backs off to the max interval
    /// during ACTIVE use — the opposite of the adaptive design (activity = fast polls).
    private var localDataChangedSinceLastPoll = false

    /// Per-window memory of the current consecutive near-full spike sequence (reset
    /// instant + when it started + whether it's confirmed — see
    /// `spikeConfirmedRateLimits`). A fresh, non-throttled near-full reading is trusted
    /// (shown as "Limit reached") only once the SAME window instance (matching reset)
    /// has stayed near-full for `spikeConfirmationMinimumAge` of consecutive fresh
    /// polls; until then the spike is held at the previous displayed value. Time-based
    /// (not poll-count-based) because the server's eventual-consistency glitch can span
    /// several polls (2026-08-11: a false 7-day 100% survived two-poll confirmation).
    /// Reset-keying means a memory from before a rollover can't confirm the new window
    /// even when no lifecycle event fired (e.g. an endpoint outage spanning the reset).
    /// Also cleared on any return-from-absence (`resumeTimers`) and account switch so a
    /// pre-absence near-full can't auto-confirm a post-absence glitch.
    /// Internal (not private) so the lifecycle extension's `resumeTimers` can clear it.
    var previouslyNearFullWindows: [String: UsageViewModel.NearFullMemory] = [:]

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
    nonisolated(unsafe) var lockObserver: NSObjectProtocol?
    nonisolated(unsafe) var unlockObserver: NSObjectProtocol?
    /// Global event monitor that detects user activity (mouse/keyboard) to resume
    /// from idle suspension. Only active while suspended — removed on resume.
    /// Read/written by lifecycle extension (`installActivityMonitor` /
    /// `removeActivityMonitor`); tests assert suspend/resume toggles this.
    /// `nonisolated(unsafe)` so the nonisolated deinit can clean it up
    /// (NSEvent.removeMonitor is thread-safe).
    nonisolated(unsafe) var activityMonitor: Any?

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
                        // Cold-start paint of persisted limits: clear rollover artifacts and
                        // mark not-fresh so a stale 100% reads as the real low % and arms no
                        // alarm until the first fetch confirms it (mirrors wake/wasEmpty paths).
                        rateLimits: cached.rateLimits?.withClearedRolloverArtifacts(),
                        rateLimitSource: cached.rateLimitSource,
                        standardLimits: cached.standardLimits,
                        accountId: accountId,
                        rateLimitsFresh: false
                    )
                    self.snapshot = result
                    self.isShowingCachedData = true
                    self.rateLimitsFresh = false
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
        accountId: String? = nil,
        rateLimitsFresh: Bool = true
    ) async -> UsageSnapshot {
        if let inflight = inflightAggregation {
            _ = await inflight.value
        }

        let agg = aggregator
        let task = Task.detached {
            agg.aggregate(rateLimits: rateLimits, rateLimitSource: rateLimitSource, standardLimits: standardLimits, accountId: accountId, rateLimitsFresh: rateLimitsFresh)
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
            rateLimitsFresh = false
            let result = await aggregateOffMain(rateLimits: nil, rateLimitsFresh: false)
            if result.totalMessages > 0, result != snapshot {
                snapshot = result
            }
            isLoading = false
            return
        }

        // Skip network when offline — show local data with the currently DISPLAYED
        // rate limits (not the raw `apiResult`, which still carries any spike glitch
        // the filter held and corrected downstream), with expired windows cleared so a
        // throttle whose reset passes while offline doesn't alarm forever. The real
        // displayed percentage keeps showing; the alarm stays suppressed until a fresh
        // fetch confirms.
        guard skipNetworkCheck || NetworkMonitor.shared.isConnected else {
            rateLimitsFresh = false
            let result = await aggregateOffMain(
                rateLimits: snapshot?.rateLimits?.withClearedExpiredWindows(),
                rateLimitSource: snapshot?.rateLimitSource,
                standardLimits: snapshot?.standardLimits,
                rateLimitsFresh: false
            )
            if result != snapshot {
                snapshot = result
            }
            isLoading = false
            errorMessage = "No internet connection"
            return
        }

        let wasEmpty = snapshot == nil
        let accountId = oauthManager.accountStore.activeAccountId

        // Show cached rate limits immediately while API call is in-flight.
        // This eliminates the empty-bars delay on launch.
        if wasEmpty, let accountId {
            let provider = oauthManager.accountStore.accounts.first { $0.id == accountId }?.provider ?? .claude
            let cached = provider == .codex
                ? CodexRateLimitFetcher.shared.cachedOrEmpty(accountId: accountId)
                : RateLimitFetcher.shared.cachedOrEmpty(accountId: accountId)
            if cached.rateLimits != nil || cached.standardLimits != nil {
                let earlyResult = await aggregateOffMain(
                    // Clear rollover artifacts on the instant-paint too: a window that just
                    // reset can carry the previous window's near-full utilization, which
                    // must not flash as "Limit reached" before the first fresh fetch.
                    rateLimits: cached.rateLimits?.withClearedRolloverArtifacts(),
                    rateLimitSource: cached.rateLimitSource,
                    standardLimits: cached.standardLimits,
                    accountId: accountId,
                    rateLimitsFresh: false
                )
                snapshot = earlyResult
                isShowingCachedData = true
                rateLimitsFresh = false
            } else {
                isLoading = true
            }
        }
        await Task.yield()

        let (api, status) = await fetchAPIData(oauthManager: oauthManager, accountId: accountId)

        // If user switched accounts while fetching, discard stale results BEFORE
        // any published state is written — otherwise the old account's data leaks
        // into the new account's display (apiResult/isShowingCachedData/lastFreshFetch).
        guard Self.shouldApplyFetchResult(
            fetchedAccountId: accountId,
            activeAccountId: oauthManager.accountStore.activeAccountId
        ) else { return }

        apiResult = api
        systemStatus = status
        isShowingCachedData = api.isCached
        // Fresh ONLY when this fetch returned unified rate-limit headers and wasn't
        // cache-served. A header-less-but-successful fetch reuses held stale limits
        // (see effectiveRateLimits below) — those must not arm the alarm / maxed bar.
        rateLimitsFresh = Self.rateLimitsAreFresh(freshRateLimits: api.rateLimits, isCached: api.isCached)
        if !api.isCached {
            lastFreshFetch = api.fetchedAt
        }

        resolveAccountIdentity(oauthManager: oauthManager, accountId: accountId, api: api)
        Self.recordThrottleEvent(api.rateLimits, source: api.isCached ? "stale-cache" : "api-fresh")
        // Hold the last good API rate limit data until replaced by a newer API response.
        // The primary /api/oauth/usage endpoint returns limits on essentially every
        // successful poll, but the legacy Messages-probe fallback returns unified
        // headers on only ~10% of polls — expiring quickly on that path causes the UI
        // to flip between API data and local estimates. Stale API data (with real
        // utilization %) is always more useful than local token estimates.
        if api.rateLimits != nil && !api.isCached {
            lastFreshRateLimitsAt = Date()
        }
        let rawEffectiveRateLimits = Self.effectiveRateLimits(
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
        // Suppress rollover artifacts: a window that just reset can briefly report the
        // previous window's near-full utilization paired with the new reset (server-side
        // eventual consistency). Showing that as "Limit reached" on a fresh window is wrong.
        let rolloverCleared = rawEffectiveRateLimits?.withClearedRolloverArtifacts()
        if let raw = rawEffectiveRateLimits, let corrected = rolloverCleared, raw != corrected {
            AppLogger.network.notice(
                "Rollover artifact suppressed (binding=\(raw.bindingWindowShortCode, privacy: .public), source=\(effectiveSource?.rawValue ?? "nil", privacy: .public)): 5h \(Int(raw.fiveHourPercent))%→\(Int(corrected.fiveHourPercent))% reset in \(Int(raw.fiveHourReset?.timeIntervalSinceNow ?? -1))s, 7d \(Int(raw.sevenDayPercent))%→\(Int(corrected.sevenDayPercent))% reset in \(Int(raw.sevenDayReset?.timeIntervalSinceNow ?? -1))s"
            )
        }
        // Confirm-before-alarming: the rollover guard above only catches a near-full
        // reading in a window's first ~10 min. But the server can return a transport-FRESH
        // yet wrong ~100% for a window many minutes into its cycle right after wake — which
        // `rateLimitsFresh` trusts, painting a false "Limit reached" (the recurrence). Hold
        // an isolated near-full spike at the previous displayed value until a second
        // consecutive fresh poll confirms it. Only runs on a genuinely fresh reading; on
        // header-less / cached polls the held value shows unaltered with the alarm gated.
        let effectiveRateLimits: RateLimitUsage?
        if rateLimitsFresh, let fresh = rolloverCleared {
            let confirmedLimits = Self.spikeConfirmedRateLimits(
                fresh: fresh,
                previousDisplayed: snapshot?.rateLimits,
                previouslyNearFull: previouslyNearFullWindows
            )
            previouslyNearFullWindows = confirmedLimits.nearFullWindows
            if !confirmedLimits.heldWindows.isEmpty {
                let shown = confirmedLimits.display
                AppLogger.network.notice(
                    "Unconfirmed rate-limit spike held (windows=\(confirmedLimits.heldWindows.sorted().joined(separator: ","), privacy: .public), source=\(effectiveSource?.rawValue ?? "nil", privacy: .public)): raw 5h \(Int(fresh.fiveHourPercent))%→\(Int(shown.fiveHourPercent))%, 7d \(Int(fresh.sevenDayPercent))%→\(Int(shown.sevenDayPercent))% — awaiting a second consecutive fresh poll before alarming"
                )
                // fetch() already cached+persisted the RAW glitch value before this
                // filter ran — write the held value back so the glitch can't survive
                // as the stale fallback a later instant-paint would re-display.
                // ONLY when every held window substitutes a real (non-zero) prior value:
                // a hold at a zeroed baseline (window just reset) must not overwrite the
                // real server reading on disk — a fabricated 0% would then survive
                // relaunch as "recent" data while the true value is lost.
                let allHeldSubstitutesReal = confirmedLimits.heldWindows.allSatisfy { window in
                    window == RateLimitUsage.fiveHourWindow
                        ? confirmedLimits.display.fiveHourUtilization > 0
                        : confirmedLimits.display.sevenDayUtilization > 0
                }
                if let accountId, allHeldSubstitutesReal {
                    RateLimitFetcher.shared.overrideCachedRateLimits(confirmedLimits.display, accountId: accountId)
                }
            }
            effectiveRateLimits = confirmedLimits.display
        } else {
            effectiveRateLimits = rolloverCleared
        }
        // Per-poll diagnostic of the raw server reading (live via `log stream`), so a
        // recurrence can be matched against the exact utilization/reset the API returned.
        if let rl = api.rateLimits, !api.isCached {
            AppLogger.network.info(
                "rate limits fresh (source=\(effectiveSource?.rawValue ?? "nil", privacy: .public)): 5h \(Int(rl.fiveHourPercent))% reset \(Int(rl.fiveHourReset?.timeIntervalSinceNow ?? -1))s status=\(rl.fiveHourStatus, privacy: .public); 7d \(Int(rl.sevenDayPercent))% reset \(Int(rl.sevenDayReset?.timeIntervalSinceNow ?? -1))s status=\(rl.sevenDayStatus, privacy: .public); binding=\(rl.bindingWindowShortCode, privacy: .public) overall=\(rl.overallStatus, privacy: .public)"
            )
        }
        // Persist whether THIS cycle's rate-limit values are genuinely fresh. The bars
        // derive per-window ALARM confirmation from this plus each window's own throttle
        // status; the displayed % is always the real (fresh or held) API value.
        let result = await aggregateOffMain(
            rateLimits: effectiveRateLimits,
            rateLimitSource: effectiveSource,
            standardLimits: api.standardLimits ?? snapshot?.standardLimits,
            accountId: accountId,
            rateLimitsFresh: rateLimitsFresh
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
                localSevenDayTokens: result.sevenDayTokens,
                accountId: accountId
            )
        }

        updateAdaptivePolling(result)
        updateSnapshot(result, api: api)
        await handlePostFetchAlerts(
            confirmedRateLimits: effectiveRateLimits,
            rateLimitsFresh: rateLimitsFresh,
            status: status
        )
        // Multi-account menu bar fan-out (no-op when toggle is off).
        // Seed with the active account's just-fetched data — RateLimitFetcher does
        // not short-circuit on cache, so seeding is what keeps net cost at N
        // requests per cycle for N accounts (instead of N+1). Seed the spike-CONFIRMED
        // value (not the raw fetch) so an unconfirmed spike can't leak into the menu bar.
        let seed: (String, RateLimitUsage)? = {
            guard let id = accountId, api.rateLimits != nil, !api.isCached,
                  let rl = effectiveRateLimits else { return nil }
            return (id, rl)
        }()
        await fetchAllAccounts(seed: seed)
    }

    // MARK: - Refresh helpers

    private func fetchAPIData(
        oauthManager: OAuthManager,
        accountId: String?
    ) async -> (APIFetchResult, ClaudeSystemStatus) {
        // Pin the token to the account this fetch was filed under. Resolving the
        // ACTIVE account's token at await-time would, after a mid-poll account
        // switch, send account B's token on a request cached and persisted under
        // account A's key.
        let accessToken: String? = if let id = accountId {
            await oauthManager.getAccessToken(for: id)
        } else {
            nil
        }

        async let fetchedStatus = StatusChecker.shared.fetchStatus()

        let provider = oauthManager.accountStore.accounts.first { $0.id == accountId }?.provider ?? .claude
        let api: APIFetchResult = if let token = accessToken, let id = accountId {
            provider == .codex
                ? await CodexRateLimitFetcher.shared.fetch(accessToken: token, accountId: id)
                : await RateLimitFetcher.shared.fetch(accessToken: token, accountId: id)
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
        // Codex identities are resolved at auth time (real account id from the JWT) —
        // the Anthropic pending-identity machinery (temp-UUID -> org-ID migration)
        // must never touch them.
        guard account.provider == .claude else { return }

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

    /// Local-only refresh for file-system events: JSONL/stats changed on disk, so
    /// re-aggregate with the currently displayed rate limits — NO network fetch and no
    /// poll-timer reset. A JSONL write means local token counts changed, not that the
    /// API state did; network polling stays on the poll timer. (Previously every
    /// debounced JSONL burst ran the full `refresh()` — an API round-trip every ~2s
    /// during an active Claude session — and reset the poll timer each time.)
    func refreshLocalData() async {
        let accountId = OAuthManager.shared.accountStore.activeAccountId
        // Capture the display inputs BEFORE suspending so the post-await guard can
        // detect a concurrent refresh() publishing newer limits mid-flight. Expired
        // windows are cleared here (the fetch paths clear via cachedOrEmpty /
        // effectiveRateLimits, but this path re-publishes the displayed value directly —
        // without clearing, a window whose reset passes between polls would keep
        // re-painting as throttled/100% on every JSONL burst until the next poll).
        let baseLimits = snapshot?.rateLimits
        let baseFresh = rateLimitsFresh
        let result = await aggregateOffMain(
            rateLimits: baseLimits?.withClearedExpiredWindows(),
            rateLimitSource: snapshot?.rateLimitSource,
            standardLimits: snapshot?.standardLimits,
            accountId: accountId,
            rateLimitsFresh: baseFresh
        )
        // Mirror refresh()'s stale-result guard: if the user switched accounts while
        // the aggregate was in flight, this result was built from the OLD account's
        // displayed rate limits — publishing it would clobber the NEW account's
        // snapshot (UsageSnapshot carries no accountId, so nothing downstream could
        // detect the mismatch).
        guard Self.shouldApplyFetchResult(
            fetchedAccountId: accountId,
            activeAccountId: OAuthManager.shared.accountStore.activeAccountId
        ) else { return }
        // Interleave guard: a timed refresh() completing during the await publishes
        // NEWER rate limits (possibly fresh/spike-corrected); a result built from the
        // pre-refresh limits must not revert them. Because FS events recur every ~2s
        // during active sessions, a single revert would otherwise stick (each burst
        // re-captures the reverted value) until the next poll. Dropping the result is
        // safe — the refresh that invalidated it aggregated the same-or-newer local data.
        guard snapshot?.rateLimits == baseLimits, rateLimitsFresh == baseFresh else { return }
        // Keep latest token counts available for 429 auto-calibration (mirrors refresh()).
        LocalUsageEstimate.latestFiveHourTokens = result.fiveHourTokens
        LocalUsageEstimate.latestSevenDayTokens = result.sevenDayTokens
        // Record activity for adaptive polling BEFORE publishing — once `snapshot` is
        // updated here, the next timed poll compares equal totals and would otherwise
        // read continuous activity as "no change" and back polling off.
        if Self.hasDataChanged(
            previousTotal: snapshot?.totalMessages ?? -1,
            previousToday: snapshot?.todayMessages ?? -1,
            newTotal: result.totalMessages,
            newToday: result.todayMessages
        ) {
            localDataChangedSinceLastPoll = true
        }
        if result != snapshot {
            snapshot = result
        }
        scheduleRolloverClear(for: result)
        // Auto mode may need to escalate/de-escalate on the new local data (context
        // health and token totals both move with JSONL writes).
        let filtered = UsageSnapshot.applyHysteresis(
            candidate: result.autoResolvedMode,
            previous: lastResolvedMode,
            snapshot: result
        )
        lastResolvedMode = filtered
        // Value-changed guard: this path runs every ~2s during active sessions, and an
        // unguarded @Published write fires objectWillChange even for the same value —
        // exactly the hidden-popover re-render churn the FS-local path exists to avoid.
        if filtered != resolvedMetricMode {
            resolvedMetricMode = filtered
        }
    }

    /// Arm a one-shot timer for the next window reset so the display rolls over the
    /// moment a countdown ends. Without this, an exhausted window keeps showing
    /// 100% / "Limit reached" after its reset passes until the next poll or JSONL
    /// burst lands (up to 5 min under adaptive backoff). The timer fires a local-only
    /// re-aggregate whose `withClearedExpiredWindows` zeroes the rolled-over window;
    /// the next timed poll then brings the real fresh value.
    private func scheduleRolloverClear(for result: UsageSnapshot) {
        rolloverClearTimer?.invalidate()
        rolloverClearTimer = nil
        let resets = [result.rateLimits?.fiveHourReset, result.rateLimits?.sevenDayReset]
            .compactMap { $0 }
            .filter { $0.timeIntervalSinceNow > 0 }
        guard let nextReset = resets.min() else { return }
        rolloverClearTimer = Timer.scheduledTimer(
            withTimeInterval: nextReset.timeIntervalSinceNow + 1,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshLocalData()
            }
        }
        rolloverClearTimer?.tolerance = 1
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
        if result != snapshot {
            snapshot = result
        }
        scheduleRolloverClear(for: result)

        // Apply hysteresis to auto-resolved mode
        let candidate = result.autoResolvedMode
        let filtered = UsageSnapshot.applyHysteresis(
            candidate: candidate,
            previous: lastResolvedMode,
            snapshot: result
        )
        lastResolvedMode = filtered
        if filtered != resolvedMetricMode {
            resolvedMetricMode = filtered
        }

        isLoading = false
    }

    private func updateAdaptivePolling(_ result: UsageSnapshot) {
        // OR in activity observed by the FS-triggered local re-aggregates since the
        // last poll — they update `snapshot`, so the totals comparison alone would
        // miss all between-poll activity.
        let dataChanged = Self.hasDataChanged(
            previousTotal: snapshot?.totalMessages ?? -1,
            previousToday: snapshot?.todayMessages ?? -1,
            newTotal: result.totalMessages,
            newToday: result.todayMessages
        ) || localDataChangedSinceLastPoll
        localDataChangedSinceLastPoll = false
        let interval = adaptivePolling.evaluate(
            dataChanged: dataChanged,
            baseInterval: refreshInterval
        )
        restartPolling(interval: interval)
    }

    private func handlePostFetchAlerts(
        confirmedRateLimits: RateLimitUsage?,
        rateLimitsFresh: Bool,
        status: ClaudeSystemStatus
    ) async {
        NotificationManager.shared.checkStatusAlerts(status: status)

        // Alert on the spike-confirmed limits, never the raw fetch — a held-but-
        // unconfirmed near-full spike must not fire a notification the bars won't show.
        if let limits = Self.alertableRateLimits(confirmed: confirmedRateLimits, rateLimitsFresh: rateLimitsFresh) {
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
        // Clear the previous account's API result too — the offline fallback path
        // in refresh() re-aggregates from apiResult, so a stale value here would
        // render the OLD account's rate limits under the new account's identity.
        apiResult = nil
        isShowingCachedData = false
        rateLimitsFresh = false
        // New account has no spike-confirmation history — start clean so its first fresh
        // near-full reading must re-confirm before alarming.
        previouslyNearFullWindows = [:]
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

    /// Formats reset timestamps for throttle-transition log lines.
    private static let throttleLogDateFormatter = ISO8601DateFormatter()

    /// Record a throttle event on the transition from normal → throttled.
    /// Each distinct throttle session counts as one event regardless of duration.
    /// Also emits one structured log line on each throttle on/off transition so a
    /// stuck/false throttle state is diagnosable after the fact.
    static func recordThrottleEvent(_ rateLimits: RateLimitUsage?, source: String = "unknown") {
        let wasThrottled = throttleTracker.wasThrottled
        let (next, timestamp) = throttleTracker.evaluate(rateLimits)
        throttleTracker = next
        if next.wasThrottled != wasThrottled {
            let window = rateLimits?.bindingWindowLabel ?? "n/a"
            let reset = rateLimits?.bindingReset.map(Self.throttleLogDateFormatter.string(from:)) ?? "none"
            if next.wasThrottled {
                AppLogger.network.info("Throttle engaged — window=\(window, privacy: .public) reset=\(reset, privacy: .public) source=\(source, privacy: .public)")
            } else {
                AppLogger.network.info("Throttle cleared — window=\(window, privacy: .public) reset=\(reset, privacy: .public) source=\(source, privacy: .public)")
            }
        }
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
        rolloverClearTimer?.invalidate()
        if let monitor = activityMonitor {
            NSEvent.removeMonitor(monitor)
        }
        // FileWatcher.deinit handles its own cleanup (cancels sources, streams, timers)
        for observer in [wakeObserver, sleepObserver, lockObserver, unlockObserver].compactMap({ $0 }) {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}
