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
    /// The hysteresis-filtered metric mode for auto mode consumers. Written only by the
    /// hysteresis step in `UsageViewModel+Refresh.swift`; the setter cannot be `private`
    /// any more because Swift's `private` is file-scoped and that step now lives in
    /// another file. The property carries no `public`, so it stays invisible outside the
    /// module either way.
    @Published var resolvedMetricMode: MetricMode = .fiveHour
    /// Per-account readings from the multi-account fan-out (menu bar + overview).
    /// Keyed by account ID; populated when the menu-bar toggle is on OR ≥ 2 eligible
    /// accounts exist (`FanOutGate`).
    @Published var perAccountReadings: [String: AccountReading] = [:]
    /// Windowed readings only — the menu-bar text path consumes this shape.
    var perAccountRateLimits: [String: RateLimitUsage] { perAccountReadings.compactMapValues(\.windows) }
    /// Per-minute API-key readings only.
    var perAccountAPILimits: [String: StandardRateLimits] { perAccountReadings.compactMapValues(\.apiLimits) }
    /// Status per provider, so the overview can show a dot on every card — not just the
    /// active account's. The active provider's entry is written by `refresh()`; any other
    /// provider with an eligible account is polled by the fan-out (each `StatusChecker`
    /// instance has its own cache + backoff). Keyed by provider, never cleared on account
    /// switch: a provider's status is a property of the provider, not of the account.
    @Published var providerStatuses: [AIProvider: ClaudeSystemStatus] = [:]
    /// Last aggregated snapshot per provider, so the overview can show each card's
    /// window token totals. Local logs are machine-wide **per provider** (every Claude
    /// account shares `~/.claude`), so this is a per-provider figure shown on that
    /// provider's cards — exactly what the detail view shows for the active account.
    /// A provider that has never been active this launch has no entry and its cards
    /// simply omit the token column.
    @Published var providerSnapshots: [AIProvider: UsageSnapshot] = [:]

    #if ENABLE_VERSION_CHECKER
    /// Available update from GitHub Releases (nil if up-to-date or not checked).
    @Published var availableUpdate: VersionChecker.UpdateInfo?
    #endif

    /// Cross-poll hysteresis state — the mode displayed on the previous poll.
    /// Reset on manual mode override and account switch.
    var lastResolvedMode: MetricMode?

    // Stored state that the lifecycle / fan-out extensions also touch is
    // declared without `private` so it remains visible across the extension
    // files in the same module. `aggregator`, `fileWatcher`, `pollingTimer`,
    // and the sleep/wake observers are read or written by
    // `UsageViewModel+Lifecycle.swift`; nothing else in the module touches them.
    /// One aggregator per provider — each owns its own reader cache + redundant-
    /// aggregation fingerprint. `aggregator` stays the Claude one (legacy name used by
    /// the lifecycle extension); `aggregator(for:)` routes by the active provider.
    let aggregator = UsageAggregator(provider: .claude)
    let codexAggregator = UsageAggregator(provider: .codex)
    /// Serializes concurrent aggregateOffMain calls — only one detached task runs at a time.
    private var inflightAggregation: Task<UsageAggregator.AggregateResult, Never>?
    var fileWatcher: FileWatcher?
    // Polling timer + NSWorkspace observers: read/written from MainActor methods,
    // but the nonisolated `deinit` must invalidate/remove them. `nonisolated(unsafe)`
    // lets the deinit touch them; Timer.invalidate and NSWorkspace.removeObserver
    // are documented thread-safe.
    nonisolated(unsafe) var pollingTimer: Timer?
    /// One-shot timer armed for the next window reset so an exhausted bar rolls over to
    /// 0% the moment its countdown ends instead of showing a stale 100% until the next
    /// poll. Re-armed on every snapshot publish (see `scheduleRolloverClear`).
    nonisolated(unsafe) var rolloverClearTimer: Timer?
    var apiResult: APIFetchResult?
    nonisolated(unsafe) var wakeObserver: NSObjectProtocol?
    nonisolated(unsafe) var sleepObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    /// Coalesces UserDefaults change notifications into a single fan-out.
    /// Read/written by `UsageViewModel+FanOut.swift`.
    var pendingFanOut: Task<Void, Never>?
    /// Monotonic stamp of the newest `fetchAllAccounts` call. Two can be in flight at
    /// once (the refresh tail awaits one directly; the observers schedule another) and
    /// the slower one must not overwrite `perAccountReadings` with an older map —
    /// only the newest call's result is applied. Read/written by `+FanOut.swift`.
    var fanOutGeneration: UInt64 = 0
    /// Bumped by `clearAccountDisplayState` (account switch / sign-out). A refresh cycle
    /// captures it at its start and re-checks it — together with the active account id —
    /// after EVERY await before publishing (`displayIsCurrent`). The account-id check alone
    /// (`shouldApplyFetchResult`) misses A → B → A: same account active again, but the
    /// display was cleared in between, and the cold aggregate from the first cycle could
    /// still publish an old snapshot / error / mode under the fresh paint.
    var displayGeneration: UInt64 = 0
    /// Last observed value of the multi-account toggle — used to filter the
    /// `UserDefaults.didChangeNotification` firehose down to actual toggle flips.
    private var lastObservedShowAllAccounts: Bool = UserDefaults.standard.bool(forKey: UserDefaultsKeys.showAllAccountsInMenuBar)

    /// Adaptive polling state machine — delegates interval logic to a pure struct.
    /// Read/written by lifecycle extension (`updatePollingInterval`, `resumeTimers`).
    var adaptivePolling = AdaptivePollingState()

    /// Timestamp of the last API response that included fresh (non-nil) rate limits.
    /// Used to expire stale fallback data — after `rateLimitStaleTTL` seconds without
    /// fresh data, the fallback is dropped so the UI transitions to StandardRateLimits.
    var lastFreshRateLimitsAt: Date?

    /// Set by `refreshLocalData()` when a file-system re-aggregate changed the message
    /// totals between timed polls; consumed (and cleared) by `updateAdaptivePolling`.
    /// Without it, the FS path keeping `snapshot` current would make every timed poll
    /// compare equal totals → "unchanged" → polling backs off to the max interval
    /// during ACTIVE use — the opposite of the adaptive design (activity = fast polls).
    var localDataChangedSinceLastPoll = false

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
    /// Set when a file-system event lands while suspended. The aggregate is deferred to
    /// `resumeTimers` so an unattended agent run does not drive a full re-aggregate every
    /// ~2 s into a popover nobody has open.
    var localDataDirtyWhileSuspended = false
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
            // Route by the active account's provider — a Codex account's cache lives in
            // CodexRateLimitFetcher, not RateLimitFetcher. Mirrors the wasEmpty routing
            // in refresh() (Task 14).
            let provider = provider(ofAccount: accountId)
            let cached = Self.cachedResult(for: provider, accountId: accountId)
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
                        provider: provider,
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

        // Account-set observer: the fan-out also feeds the multi-account overview, which
        // is gated on the eligible-account COUNT (`FanOutGate`), not the toggle. Adding,
        // removing or signing out an account must re-run it (or clear it) promptly.
        OAuthManager.shared.accountStore.$accounts
            .map(\.count)
            .removeDuplicates()
            .dropFirst()
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleFanOut()
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
        provider: AIProvider = .claude,
        rateLimitsFresh: Bool = true,
        applySideEffects: Bool = true,
        providerWide: Bool = false
    ) async -> UsageSnapshot {
        // Loop, don't check once: N callers queued behind one in-flight task all resumed
        // together, each started its own detached task, and the last assignment won —
        // the others became untracked. The locks inside `UsageAggregator` / `TokenLedger`
        // kept that safe, but it was wasted work under a comment claiming serialization.
        while let inflight = inflightAggregation {
            _ = await inflight.value
            if inflightAggregation == inflight {
                break // the owner finished without clearing the slot — take it
            }
        }
        let accounts = OAuthManager.shared.accountStore.accounts
        // Decided here, once, for all seven callers: the detail view gets per-account data
        // only when two or more ChatGPT Codex accounts exist; the overview's background
        // pass for another provider always asks for everything.
        let attribution: Attribution = providerWide ? .all : AccountStore.attribution(for: accountId, provider: provider, accounts: accounts)

        let agg = aggregator(for: provider)
        let task = Task.detached {
            agg.aggregate(rateLimits: rateLimits, rateLimitSource: rateLimitSource, standardLimits: standardLimits, accountId: accountId, rateLimitsFresh: rateLimitsFresh, attribution: attribution)
        }
        inflightAggregation = task
        var result = await task.value
        // Pay-per-token accounts: the cost rows are a real bill, not subscription value —
        // but only when the CLI's rollouts can be attributed to the key (no ChatGPT-backed
        // Codex account that could have produced them under a subscription).
        let billed = accountId.map { AccountStore.billsLocalCodexCosts(accounts: accounts, activeId: $0) } ?? false
        result.detail.costIsBilled = billed
        result.providerWide.costIsBilled = billed

        // The overview's cards read this map; it must never carry an attributed snapshot
        // (two Codex cards would otherwise show one account's turns). A nil snapshot on an
        // account switch must not erase a provider's last known aggregate either — only
        // real results land here.
        // Value-changed guard: this runs on every ~2s FS burst, and an unguarded @Published
        // write fires objectWillChange even when the value is unchanged — the same churn
        // `refreshLocalData` guards its publishes against (see UsageViewModel+Refresh.swift).
        if providerSnapshots[provider] != result.providerWide {
            providerSnapshots[provider] = result.providerWide
        }

        // Apply side effects before clearing inflightAggregation so the next
        // caller sees consistent RateLimitFetcher state. The observed-model list feeds
        // the Claude Messages-probe fallback only — gpt-* IDs must never land there.
        // `applySideEffects` is false for the overview's background aggregation of a
        // NON-active provider: `activeUserModel` / observed models are global probe state
        // for the account being polled, and a background pass for another account must
        // not overwrite them every cycle.
        if applySideEffects, result.effects.provider == .claude {
            RateLimitFetcher.shared.activeUserModel = result.effects.activeUserModel
            if let id = result.effects.accountId {
                RateLimitFetcher.shared.setObservedModels(result.effects.observedModels, accountId: id)
            }
        }
        // Only the owner clears the slot: an unconditional nil could drop a newer
        // caller's task and let a third caller run alongside it.
        if inflightAggregation == task {
            inflightAggregation = nil
        }
        return result.detail
    }

    /// - Parameter skipNetworkCheck: When true, bypasses the offline guard. Used on wake
    ///   when NWPathMonitor may briefly report disconnected while WiFi reconnects.

    /// The refresh cycle currently running, so concurrent callers join it instead of
    /// starting a second one.
    private var inflightRefresh: (task: Task<Void, Never>, skipNetworkCheck: Bool, accountId: String?)?

    /// Run a refresh cycle, coalescing with one already in flight.
    ///
    /// Waking a locked Mac starts two on its own — `didWakeNotification` schedules one at
    /// wake + 3 s and `sessionDidBecomeActiveNotification` another at unlock + 1 s — and
    /// post-wake networking is exactly when a request is slow. The slower cycle then
    /// finishes LAST and unconditionally overwrites `apiResult`, `rateLimitsFresh` and the
    /// snapshot with its older reading, re-runs the spike filter against the newer cycle's
    /// already-updated `previouslyNearFullWindows`, and can write the stale value back to
    /// the persisted cache. Joining also halves the multi-account fan-out.
    public func refresh(skipNetworkCheck: Bool = false) async {
        // Only join a cycle at least as strong as this one. A wake/unlock refresh passes
        // `skipNetworkCheck: true` precisely to bypass a NWPathMonitor that still reports
        // disconnected; joining a plain timer cycle already in its offline branch would
        // discard that intent and leave the next real attempt a whole poll interval away.
        //
        // Loop rather than check once: several callers can be parked on the same weaker
        // cycle, and whichever resumes first registers its own task — the others must
        // re-evaluate against THAT cycle, not start a third one.
        //
        // A cycle is only joinable if it is fetching the account that is active NOW.
        // `switchAccount` clears the display and schedules `refresh()`; if that call
        // joined the previous account's still-running cycle, that cycle's result would be
        // (correctly) discarded by `shouldApplyFetchResult` and the new account would sit
        // on an empty, spinning popover until the next timer tick — up to 5 min under
        // adaptive backoff. A cycle for another account is waited out (so it cannot land
        // on top of ours) and then a fresh one runs.
        let activeAccountId = OAuthManager.shared.accountStore.activeAccountId
        while let inflight = inflightRefresh {
            if inflight.accountId == activeAccountId, inflight.skipNetworkCheck || !skipNetworkCheck {
                await inflight.task.value
                return
            }
            // A weaker cycle, or one for a different account, is in flight — let it
            // finish, then re-check.
            await inflight.task.value
            // Release the finished slot if its owner has not reached its own cleanup
            // yet. Awaiting an already-completed task resumes synchronously, so without
            // this a waiter that resumed BEFORE the owner would re-read the same
            // finished cycle and loop forever with no suspension point, wedging the
            // main actor. Reachable whenever `switchAccount` lands mid-cycle.
            if inflightRefresh?.task == inflight.task {
                inflightRefresh = nil
            }
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performRefresh(skipNetworkCheck: skipNetworkCheck)
        }
        inflightRefresh = (task, skipNetworkCheck, activeAccountId)
        await task.value
        // Only release the slot if it is still ours. A waiter that resumed before us may
        // already have registered its own cycle; clearing that would let the next caller
        // start a concurrent refresh — the exact double-cycle this method exists to stop.
        if inflightRefresh?.task == task {
            inflightRefresh = nil
        }
    }

    /// Assign only when the value actually changed. `@Published` fires on every write,
    /// equal or not, and these properties are written once per poll from a cycle whose
    /// awaits put each write in its own run-loop tick — so an unchanged poll re-rendered
    /// the open popover several times over.
    func setIfChanged<T: Equatable>(_ storage: inout T, _ newValue: T) {
        guard storage != newValue else { return }
        storage = newValue
    }

    /// Instance form of `displayIsCurrent(captured:current:fetchedAccountId:activeAccountId:)`
    /// against the live generation and active account.
    func displayIsCurrent(_ captured: UInt64, accountId: String?) -> Bool {
        Self.displayIsCurrent(
            captured: captured,
            current: displayGeneration,
            fetchedAccountId: accountId,
            activeAccountId: OAuthManager.shared.accountStore.activeAccountId
        )
    }

    /// Reset hysteresis state — called when user manually selects a mode or switches accounts.
    func resetHysteresis() {
        lastResolvedMode = nil
    }

    /// Re-point the view model at whichever account is active NOW.
    ///
    /// Adding and removing accounts change `AccountStore.activeAccountId` without going
    /// through `switchAccount` — `OAuthManager.activateCodexAccount` / the Claude add path
    /// both call `setActive` directly, and `AccountStore.remove` reassigns it to
    /// `accounts.first`. Without this, the previous account's state survives the change and
    /// `refresh()` takes the stale-fallback branch (`snapshot != nil`, so no instant-paint
    /// from the new account's cache), rendering the OLD account's rate limits under the NEW
    /// account's identity for up to the 24 h stale TTL. Cross-provider that means Anthropic
    /// 5h/7d percentages displayed under a Codex chip.
    func syncToActiveAccount() {
        guard let activeId = OAuthManager.shared.accountStore.activeAccountId else {
            // Signing out the LAST account sets `activeAccountId` to nil. Returning here
            // would leave the removed account's snapshot in place — and the menu bar reads
            // `snapshot?.rateLimits` with no auth gate, so its percentage and star stayed
            // on screen for an account that no longer exists.
            clearAccountDisplayState()
            return
        }
        switchAccount(to: activeId)
    }

    /// Drop everything that describes a specific account. Shared by `switchAccount` and
    /// the signed-out path so the two can never diverge. Bumps `displayGeneration` so
    /// any refresh / local-refresh / repaint cycle still in flight for the previous
    /// display discards its result instead of publishing it here.
    func clearAccountDisplayState() {
        displayGeneration &+= 1
        lastResolvedMode = nil
        snapshot = nil
        // The offline fallback path re-aggregates from `apiResult`, so a stale value here
        // would render the OLD account's rate limits under the new account's identity.
        apiResult = nil
        // The status feed follows the provider — drop the old one until the next fetch.
        systemStatus = nil
        isShowingCachedData = false
        rateLimitsFresh = false
        // No spike-confirmation history carries over — the next account's first fresh
        // near-full reading must re-confirm before alarming.
        previouslyNearFullWindows = [:]
        lastFreshFetch = nil
        // Without this the next account's first header-less poll can still resolve the OLD
        // account's limits through `effectiveRateLimits`' stale window.
        lastFreshRateLimitsAt = nil
        errorMessage = nil
    }

    /// Switch to a different account and refresh data.
    func switchAccount(to accountId: String) {
        OAuthManager.shared.accountStore.setActive(id: accountId)
        clearAccountDisplayState()
        isLoading = true
        OAuthManager.shared.objectWillChange.send()
        Task { await refresh() } // refresh() also calls fetchAllAccounts() at its tail.
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
