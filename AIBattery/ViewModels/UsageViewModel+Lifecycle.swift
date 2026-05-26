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
                let accountId = OAuthManager.shared.accountStore.activeAccountId
                if let accountId {
                    let cached = RateLimitFetcher.shared.cachedOrEmpty(accountId: accountId)
                    if cached.rateLimits != nil || cached.standardLimits != nil {
                        let result = await self.aggregateOffMain(
                            rateLimits: cached.rateLimits,
                            rateLimitSource: cached.rateLimitSource,
                            standardLimits: cached.standardLimits,
                            accountId: accountId
                        )
                        if result != self.snapshot { self.snapshot = result }
                        self.isShowingCachedData = true
                    }
                }

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

        // Screen unlock — resume timers and refresh.
        unlockObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.resumeTimers()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await self.refresh(skipNetworkCheck: true)
            }
        }
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
    func resumeFromUserInteraction() {
        resumeTimers()
        Task { await refresh(skipNetworkCheck: true) }
    }

    /// Resume polling and FileWatcher fallback timer after wake or activity.
    func resumeTimers() {
        guard isSuspended else { return }
        isSuspended = false
        removeActivityMonitor()
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
