import Foundation
import AppKit

// MARK: - Lifecycle / polling / observers extracted from UsageViewModel

//
// File-watcher setup, sleep/wake/screen-lock observer wiring, idle
// suspend / activity-monitor resume, and polling timer plumbing. None of
// these touch published state directly — they only schedule work and call
// back into the core `refresh()` orchestration.
//
// The `deinit` cleanup that mirrors these observers must stay in the main
// file (Swift doesn't allow deinit in extensions).

extension UsageViewModel {
    // MARK: - One-time setup (init)

    func setupFileWatcher() {
        fileWatcher = FileWatcher { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.aggregator.invalidate()
                // Local-only: a JSONL/stats write changed local token counts, not the
                // API state. Re-aggregate with the currently displayed rate limits and
                // leave the poll timer alone — restarting it here starved network polls
                // during continuous activity (every ~2s burst reset the countdown), and
                // the old full refresh() fired an API round-trip per burst on top.
                await self.refreshLocalData()
            }
        }
        fileWatcher?.startWatching()
    }

    /// Pause polling before sleep — avoids wasted timer fires while the
    /// system is suspended and ensures a clean lifecycle.
    /// On wake, reset adaptive polling and refresh immediately.
    func setupSleepWakeObservers() {
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.suspendTimers()
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
                await self.repaintCachedNotFresh()

                self.resumeTimers()

                // Wait for WiFi to reconnect after sleep before hitting the API.
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                // Skip network check — NWPathMonitor may still report disconnected
                // while WiFi is reconnecting. Let the API call try and timeout naturally.
                await self.refresh(skipNetworkCheck: true)
            }
        }

        // Screen lock — suspend all timers immediately.
        lockObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.suspendTimers()
            }
        }

        // Screen unlock — resume timers and refresh. Repaint from cache first: the
        // pre-lock snapshot may carry `rateLimitsFresh=true` with hours-old data (a
        // window can reset during a long lock), and only the wake path used to drop it.
        unlockObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.repaintCachedNotFresh()
                self.resumeTimers()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await self.refresh(skipNetworkCheck: true)
            }
        }
    }

    /// Repaint the display from the persisted cache with the freshness flag dropped —
    /// the return-from-absence baseline (wake, unlock, idle resume). The pre-absence
    /// snapshot may be hours old yet still marked `rateLimitsFresh=true`, which would
    /// keep the "Limit reached" alarm armed on stale data until the post-absence fetch
    /// lands. The cache path applies `withClearedExpiredWindows` (via `cachedOrEmpty`)
    /// and `withClearedRolloverArtifacts` here, so a window that reset during the
    /// absence paints as rolled over, not exhausted. Drops the freshness flag even
    /// when the cache is empty.
    func repaintCachedNotFresh() async {
        rateLimitsFresh = false
        guard let accountId = OAuthManager.shared.accountStore.activeAccountId else { return }
        let cached = RateLimitFetcher.shared.cachedOrEmpty(accountId: accountId)
        guard cached.rateLimits != nil || cached.standardLimits != nil else { return }
        let result = await aggregateOffMain(
            // Clear rollover artifacts so a just-reset window's carried-over
            // near-full utilization doesn't paint "Limit reached" on return.
            rateLimits: cached.rateLimits?.withClearedRolloverArtifacts(),
            rateLimitSource: cached.rateLimitSource,
            standardLimits: cached.standardLimits,
            accountId: accountId,
            rateLimitsFresh: false
        )
        // Mirror refresh()'s account-switch guard for the suspension window.
        guard Self.shouldApplyFetchResult(
            fetchedAccountId: accountId,
            activeAccountId: OAuthManager.shared.accountStore.activeAccountId
        ) else { return }
        if result != snapshot {
            snapshot = result
        }
        isShowingCachedData = true
        rateLimitsFresh = false
    }

    // MARK: - Refresh interval

    var refreshInterval: TimeInterval {
        Self.clampedRefreshInterval(UserDefaults.standard.double(forKey: UserDefaultsKeys.refreshInterval))
    }

    // MARK: - Idle suspend / activity-monitor resume

    /// Suspend polling and FileWatcher fallback timer.
    /// Called on screen lock or idle threshold reached.
    /// Installs a global event monitor so the first user interaction resumes polling.
    func suspendTimers() {
        guard !isSuspended else { return }
        isSuspended = true
        pollingTimer?.invalidate()
        pollingTimer = nil
        fileWatcher?.suspendFallbackTimer()
        installActivityMonitor()
    }

    /// Resume from user interaction (e.g., clicking the menu bar icon).
    /// Public entry point for StatusBarManager — the global event monitor may not
    /// fire without Accessibility permission, so direct interaction is the reliable path.
    /// Repaints from cache only when actually returning from suspension — an ordinary
    /// click while active must not drop the freshness flag (that would gate a
    /// legitimately armed alarm every time the popover opens).
    func resumeFromUserInteraction() {
        let wasSuspended = isSuspended
        resumeTimers()
        Task {
            if wasSuspended {
                await repaintCachedNotFresh()
            }
            await refresh(skipNetworkCheck: true)
        }
    }

    /// Resume polling and FileWatcher fallback timer after wake or activity.
    func resumeTimers() {
        guard isSuspended else { return }
        isSuspended = false
        removeActivityMonitor()
        // Return-from-absence choke point (wake, screen unlock, idle resume). Forget the
        // previous-poll near-full memory so a pre-absence near-full reading can't auto-
        // confirm a post-absence server glitch — the first fresh reading after an absence
        // must re-confirm before it can arm "Limit reached" (see spikeConfirmedRateLimits).
        previouslyNearFullWindows = [:]
        adaptivePolling.unchangedCycles = 0
        restartPolling(interval: refreshInterval)
        fileWatcher?.resumeFallbackTimer()
    }

    /// Install a global event monitor that fires on the first mouse/keyboard event
    /// after idle suspension. Resumes timers and triggers an immediate refresh.
    /// Only active while suspended — removed on resume to avoid overhead.
    func installActivityMonitor() {
        guard activityMonitor == nil else { return }
        activityMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isSuspended else { return }
                self.resumeTimers()
                await self.repaintCachedNotFresh()
                await self.refresh(skipNetworkCheck: true)
            }
        }
    }

    func removeActivityMonitor() {
        if let monitor = activityMonitor {
            NSEvent.removeMonitor(monitor)
            activityMonitor = nil
        }
    }

    // MARK: - Polling timer

    func startPolling() {
        restartPolling(interval: refreshInterval)
    }

    /// Restart the polling timer with the given interval.
    func restartPolling(interval: TimeInterval) {
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
}
