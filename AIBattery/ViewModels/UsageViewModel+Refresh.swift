import Combine
import Foundation
import SwiftUI

/// The refresh cycle: the network/aggregate pass (`performRefresh`), the file-system
/// local-only pass (`refreshLocalData`), and the publish helpers they share.
///
/// Split out of `UsageViewModel.swift`, which had grown past the 800-line ceiling in
/// CLAUDE.md. Members reached from here are `internal` rather than `private` because
/// Swift's `private` is file-scoped — the same reason `UsageViewModel+Lifecycle.swift`
/// already does this.
@MainActor
extension UsageViewModel {
    func performRefresh(skipNetworkCheck: Bool) async {
        // Skip polling cycle when suspended due to idle or screen lock.
        // Allow explicit resume refreshes through by checking skipNetworkCheck (wake path).
        guard !isSuspended || skipNetworkCheck else { return }
        // Captured once; every publish below is gated on it still being current.
        let generation = displayGeneration

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

        // Skip network work when not authenticated — still aggregate local data
        // (Claude's, the historical default for the signed-out state).
        guard oauthManager.isAuthenticated else {
            rateLimitsFresh = false
            let result = await aggregateOffMain(rateLimits: nil, rateLimitsFresh: false)
            // Generation only: this branch has no account to compare (signed-out local view).
            guard generation == displayGeneration else { return }
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
            let offlineAccountId = oauthManager.accountStore.activeAccountId
            let result = await aggregateOffMain(
                rateLimits: snapshot?.rateLimits?.withClearedExpiredWindows(),
                rateLimitSource: snapshot?.rateLimitSource,
                standardLimits: snapshot?.standardLimits,
                accountId: offlineAccountId,
                provider: provider(ofAccount: offlineAccountId),
                rateLimitsFresh: false
            )
            guard displayIsCurrent(generation, accountId: offlineAccountId) else { return }
            if result != snapshot {
                snapshot = result
            }
            isLoading = false
            errorMessage = "No internet connection"
            return
        }

        let wasEmpty = snapshot == nil
        let accountId = oauthManager.accountStore.activeAccountId
        // Resolved once and reused for every aggregate / write-back / status routing
        // decision below — each provider has its own local data layer, fetcher cache,
        // and status feed.
        let accountProvider = provider(ofAccount: accountId)

        // Show cached rate limits immediately while API call is in-flight.
        // This eliminates the empty-bars delay on launch.
        if wasEmpty, let accountId {
            let cached = Self.cachedResult(for: accountProvider, accountId: accountId)
            if cached.rateLimits != nil || cached.standardLimits != nil {
                let earlyResult = await aggregateOffMain(
                    // Clear rollover artifacts on the instant-paint too: a window that just
                    // reset can carry the previous window's near-full utilization, which
                    // must not flash as "Limit reached" before the first fresh fetch.
                    rateLimits: cached.rateLimits?.withClearedRolloverArtifacts(),
                    rateLimitSource: cached.rateLimitSource,
                    standardLimits: cached.standardLimits,
                    accountId: accountId,
                    provider: accountProvider,
                    rateLimitsFresh: false
                )
                // The instant-paint awaited a (possibly cold) aggregate: same guard.
                guard displayIsCurrent(generation, accountId: accountId) else { return }
                snapshot = earlyResult
                isShowingCachedData = true
                rateLimitsFresh = false
            } else {
                isLoading = true
            }
        }
        await Task.yield()

        let (api, status) = await fetchAPIData(oauthManager: oauthManager, accountId: accountId)

        // If user switched accounts (or the display was cleared) while fetching, discard
        // stale results BEFORE any published state is written — otherwise the old
        // account's data leaks into the new account's display
        // (apiResult/isShowingCachedData/lastFreshFetch).
        guard displayIsCurrent(generation, accountId: accountId) else { return }

        apiResult = api
        // Value-equal writes still publish, and these are separated by awaits, so each
        // one landed in its own run-loop tick and re-rendered the open popover. A poll
        // that changed nothing cost four or five full re-evaluations.
        setIfChanged(&systemStatus, status)
        // Mirror into the per-provider map the overview's cards read from.
        if providerStatuses[accountProvider] != status {
            providerStatuses[accountProvider] = status
        }
        setIfChanged(&isShowingCachedData, api.isCached)
        // Fresh ONLY when this fetch returned unified rate-limit headers and wasn't
        // cache-served. A header-less-but-successful fetch reuses held stale limits
        // (see effectiveRateLimits below) — those must not arm the alarm / maxed bar.
        setIfChanged(&rateLimitsFresh, Self.rateLimitsAreFresh(freshRateLimits: api.rateLimits, isCached: api.isCached))
        if !api.isCached {
            setIfChanged(&lastFreshFetch, api.fetchedAt)
        }

        resolveAccountIdentity(oauthManager: oauthManager, accountId: accountId, api: api)
        Self.recordThrottleEvent(api.rateLimits, accountId: accountId, source: api.isCached ? "stale-cache" : "api-fresh")
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
                    // Route the write-back by provider — writing a Codex correction into
                    // RateLimitFetcher's (Claude) cache/`aibattery_rateLimits_<id>` blob
                    // would leave the raw glitch alive in the Codex fetcher's own cache/
                    // `aibattery_codexRateLimits_<id>` blob, surviving relaunch as a false
                    // "Limit reached" (the false-alarm bug class v2.6.1 fixed for Claude).
                    Self.overrideCachedRateLimits(confirmedLimits.display, for: accountProvider, accountId: accountId)
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
            // A stale per-minute reading must not outlive its own reset (API-key accounts).
            standardLimits: api.standardLimits ?? snapshot?.standardLimits?.withClearedExpiredWindows(),
            accountId: accountId,
            provider: accountProvider,
            rateLimitsFresh: rateLimitsFresh
        )
        // A cold scan can take seconds; the user may have switched (or switched and
        // come back) meanwhile. Nothing below may publish for a display that is gone.
        guard displayIsCurrent(generation, accountId: accountId) else { return }
        logCorruptionMetrics()

        // Keep latest token counts available for 429 auto-calibration, and calibrate the
        // local estimate from fresh utilization — Claude only. Codex snapshots never use
        // the local estimate, and the `latest*Tokens` globals feed a header-less-429
        // calibration on whichever account is active next: leaving Codex token counts
        // there could seed a Claude limit from Codex math right after an account switch.
        LocalUsageEstimate.recordLatestTokens(
            fiveHour: result.fiveHourTokens, sevenDay: result.sevenDayTokens, provider: accountProvider
        )
        if accountProvider == .claude,
           // Auto-calibrate local usage limits when API returns fresh utilization data.
           // This lets us estimate percentages from local tokens when the API is unavailable.
           let rl = api.rateLimits, !api.isCached {
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
            status: status,
            provider: accountProvider,
            accountId: accountId
        )
        // Multi-account menu bar fan-out (no-op when toggle is off).
        // Seed with the active account's just-fetched data — RateLimitFetcher does not
        // short-circuit on cache, so seeding is what keeps net cost at N requests per
        // cycle for N accounts (instead of N+1). Seed the spike-CONFIRMED windows (not
        // the raw fetch) so an unconfirmed spike can't leak into the menu bar; an
        // API-key account has no windows at all and seeds from its per-minute limits,
        // which is why the shape here is an `AccountReading` rather than windows alone.
        let seed: (String, AccountReading)? = {
            guard let id = accountId, !api.isCached else { return nil }
            if let rl = effectiveRateLimits, api.rateLimits != nil {
                return (id, AccountReading(
                    windows: rl, apiLimits: nil, fetchedAt: api.fetchedAt,
                    isCached: false, source: api.rateLimitSource
                ))
            }
            guard let reading = AccountReading(api: api) else { return nil }
            return (id, reading)
        }()
        // The active account is excluded whether or not it seeded: an unseeded re-fetch
        // would spend a second request on the endpoint that just served it from cache.
        await fetchAllAccounts(seed: seed, excluding: accountId)
    }

    // MARK: - Refresh helpers

    private func logCorruptionMetrics() {
        let corruptLines = SessionLogReader.shared.lastCorruptLineCount + CodexSessionLogReader.shared.lastCorruptLineCount
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
        let accountProvider = provider(ofAccount: accountId)
        let generation = displayGeneration
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
            provider: accountProvider,
            rateLimitsFresh: baseFresh
        )
        // Mirror refresh()'s stale-result guard: if the user switched accounts while
        // the aggregate was in flight, this result was built from the OLD account's
        // displayed rate limits — publishing it would clobber the NEW account's
        // snapshot (UsageSnapshot carries no accountId, so nothing downstream could
        // detect the mismatch).
        guard displayIsCurrent(generation, accountId: accountId) else { return }
        // Interleave guard: a timed refresh() completing during the await publishes
        // NEWER rate limits (possibly fresh/spike-corrected); a result built from the
        // pre-refresh limits must not revert them. Because FS events recur every ~2s
        // during active sessions, a single revert would otherwise stick (each burst
        // re-captures the reverted value) until the next poll. Dropping the result is
        // safe — the refresh that invalidated it aggregated the same-or-newer local data.
        guard snapshot?.rateLimits == baseLimits, rateLimitsFresh == baseFresh else { return }
        // Keep latest token counts available for 429 auto-calibration (mirrors refresh();
        // Claude-gated inside — this path fires every ~2s during a Codex session).
        LocalUsageEstimate.recordLatestTokens(
            fiveHour: result.fiveHourTokens, sevenDay: result.sevenDayTokens, provider: accountProvider
        )
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
        setIfChanged(&errorMessage, Self.refreshErrorMessage(
            hasRateLimits: api.rateLimits != nil,
            hasStandardLimits: api.standardLimits != nil,
            hasProfile: api.profile != nil,
            hasStandardRateLimitHeaders: api.hasStandardRateLimitHeaders,
            totalMessages: result.totalMessages,
            authError: api.authError,
            provider: result.provider,
            endpointUnavailable: api.endpointUnavailable
        ))
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

        setIfChanged(&isLoading, false)
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

    /// - Parameter accountId: the account the reading was FETCHED for — never re-read
    ///   from the store here, or a mid-cycle switch keys the "already fired" latch (and
    ///   the notification) to the new account with the old account's limits.
    private func handlePostFetchAlerts(
        confirmedRateLimits: RateLimitUsage?,
        rateLimitsFresh: Bool,
        status: ClaudeSystemStatus,
        provider: AIProvider,
        accountId: String?
    ) async {
        NotificationManager.shared.checkStatusAlerts(
            status: status,
            components: StatusChecker.shared(for: provider).config.knownComponents
        )

        // Alert on the spike-confirmed limits, never the raw fetch — a held-but-
        // unconfirmed near-full spike must not fire a notification the bars won't show.
        if let limits = Self.alertableRateLimits(confirmed: confirmedRateLimits, rateLimitsFresh: rateLimitsFresh) {
            // Scoped to the account the reading belongs to — a global latch let an account
            // switch clear another account's "already fired" and re-alert on return.
            NotificationManager.shared.checkRateLimitAlerts(rateLimits: limits, accountId: accountId)
        }

        #if ENABLE_VERSION_CHECKER
        if availableUpdate == nil {
            let found = await VersionChecker.shared.checkForUpdate()
            withAnimation(MotionConstants.standard) { availableUpdate = found }
        }
        #endif
    }
}
