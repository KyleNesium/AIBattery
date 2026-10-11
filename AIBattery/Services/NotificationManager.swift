import Foundation
import os
import UserNotifications

/// Fires macOS notifications for status-page outages across all tracked components.
/// Uses UNUserNotificationCenter for native delivery with the app's own icon.
/// Deduplicates: only fires once per outage, resets when service recovers.
@MainActor
public final class NotificationManager {
    public static let shared = NotificationManager()

    /// Tracks keys that have already fired while their condition is active.
    private var hasFired = Set<String>()

    /// Pending alerts queued for batching (flushed after 500ms).
    private var pendingAlerts: [(title: String, body: String)] = []
    private var flushTask: Task<Void, Never>?
    private static let batchDelay: UInt64 = 500_000_000 // 500ms in nanoseconds

    private init() {
        migrateAlertKeys()
    }

    // MARK: - Public

    /// Fire test notifications for the given feed's components (verifies delivery
    /// works). Callers pass the active provider's components so a Codex user gets
    /// OpenAI names, not "claude.ai is down".
    func testAlerts(components: [StatusComponent] = StatusChecker.knownComponents) {
        for component in components {
            hasFired.remove(component.alertKey)
            checkComponentStatus(key: component.alertKey, label: component.name, indicator: .majorOutage)
        }
    }

    /// Check status page and fire alerts for the given feed's components when alerts
    /// are enabled. Defaults to the Claude feed; callers pass the active provider's.
    func checkStatusAlerts(status: ClaudeSystemStatus, components: [StatusComponent] = StatusChecker.knownComponents) {
        guard UserDefaults.standard.bool(forKey: UserDefaultsKeys.alertStatus) else { return }
        for component in components {
            let indicator = status.componentStatuses[component.id] ?? .unknown
            checkComponentStatus(key: component.alertKey, label: component.name, indicator: indicator)
        }
    }

    /// Check rate limits and fire alert when usage crosses the configured threshold.
    /// Deduplicates per window: fires once when crossing, resets when dropping below.
    func checkRateLimitAlerts(rateLimits: RateLimitUsage, accountId: String? = nil) {
        let enabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.alertRateLimit)
        guard enabled else { return }

        let threshold = UserDefaults.standard.double(forKey: UserDefaultsKeys.rateLimitThreshold)
        let effectiveThreshold = threshold > 0 ? threshold : 80.0

        // A credit budget mirrors one number onto both windows — one alert, not two
        // identical ones batched into "Multiple alerts".
        if rateLimits.isCreditBudget {
            checkRateLimitWindow(
                key: Self.rateLimitKey("rateLimitCredits", accountId: accountId),
                label: "Credits",
                percent: rateLimits.sevenDayPercent,
                threshold: effectiveThreshold
            )
            return
        }

        let labels = Self.windowLabels(for: rateLimits)
        checkRateLimitWindow(
            key: Self.rateLimitKey("rateLimit5h", accountId: accountId),
            label: labels.fiveHour,
            percent: rateLimits.fiveHourPercent,
            threshold: effectiveThreshold
        )
        checkRateLimitWindow(
            key: Self.rateLimitKey("rateLimit7d", accountId: accountId),
            label: labels.secondary,
            percent: rateLimits.sevenDayPercent,
            threshold: effectiveThreshold
        )
    }

    /// Scope a rate-limit dedup key to its account. The windows belong to one account, so
    /// a global key made the latch follow whichever account happened to poll last:
    /// switching from a Claude account at 85% to a Codex account at 10% cleared the latch,
    /// and switching back re-alerted — while a second account crossing the threshold right
    /// after the first got no alert at all. Keys stay unsuffixed when no account is known
    /// so existing behaviour (and `migrateAlertKeys`) is unchanged.
    nonisolated static func rateLimitKey(_ base: String, accountId: String?) -> String {
        guard let accountId, !accountId.isEmpty else { return base }
        return "\(base)_\(accountId)"
    }

    /// Drop an account's latched rate-limit keys. Called when an account is removed so a
    /// re-added account starts clean rather than inheriting a stale "already fired".
    func clearRateLimitAlerts(accountId: String) {
        hasFired = hasFired.filter { !$0.hasSuffix("_\(accountId)") }
    }

    /// Notification vocabulary per provider: Anthropic says "7-Day", OpenAI says "Weekly".
    nonisolated static func windowLabels(for provider: AIProvider) -> (fiveHour: String, secondary: String) {
        ("5-Hour", provider.secondaryWindowLabel)
    }

    /// Reading-aware variant: a Codex credit budget mirrors one number onto both windows,
    /// so both alerts are simply "Credits".
    nonisolated static func windowLabels(for rateLimits: RateLimitUsage) -> (fiveHour: String, secondary: String) {
        rateLimits.isCreditBudget ? ("Credits", "Credits") : windowLabels(for: rateLimits.provider)
    }

    /// Pure function for testability: whether an alert should fire given the current state.
    nonisolated static func shouldAlert(percent: Double, threshold: Double, previouslyFired: Bool) -> Bool {
        percent >= threshold && !previouslyFired
    }

    /// Request notification permission from macOS. Fire-and-forget — the system
    /// remembers the user's choice, so subsequent calls are no-ops.
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error {
                AppLogger.general.warning("Notification permission request failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Private

    private func checkRateLimitWindow(key: String, label: String, percent: Double, threshold: Double) {
        if Self.shouldAlert(percent: percent, threshold: threshold, previouslyFired: hasFired.contains(key)) {
            hasFired.insert(key)
            send(
                title: "AI Battery: \(label) rate limit",
                body: "\(label) usage at \(Int(percent))% (threshold: \(Int(threshold))%)."
            )
        } else if percent < threshold {
            hasFired.remove(key)
        }
    }

    private func checkComponentStatus(key: String, label: String, indicator: StatusIndicator) {
        let isDown = indicator != .operational && indicator != .unknown
        if isDown {
            if !hasFired.contains(key) {
                hasFired.insert(key)
                let statusText = indicator.displayName
                send(
                    title: "AI Battery: \(label) is down",
                    body: "\(label) status: \(statusText)."
                )
            }
        } else {
            hasFired.remove(key)
        }
    }

    /// Queue a notification for batched delivery.
    /// If multiple alerts arrive within 500ms, they are combined into a single notification.
    private func send(title: String, body: String) {
        pendingAlerts.append((title: title, body: body))

        // Cancel any pending flush and restart the timer
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.batchDelay)
            guard !Task.isCancelled else { return }
            self?.flushPendingAlerts()
        }
    }

    /// Flush pending alerts — single alert sent as-is, multiple combined.
    private func flushPendingAlerts() {
        let alerts = pendingAlerts
        pendingAlerts.removeAll()
        flushTask = nil

        guard !alerts.isEmpty else { return }

        let title: String
        let body: String
        if alerts.count == 1 {
            title = alerts[0].title
            body = alerts[0].body
        } else {
            title = "AI Battery: Multiple alerts"
            body = alerts.map(\.body).joined(separator: "\n")
        }

        deliverNotification(title: title, body: body)
    }

    /// One-time migration from legacy per-component alert keys to the single toggle.
    /// If any old key was enabled, enable the unified alertStatus key.
    private func migrateAlertKeys() {
        Self.migrateAlertKeys(defaults: .standard)
    }

    /// Legacy alert keys from v1.5–v1.6.2 (per-component toggles).
    nonisolated static let legacyAlertKeys = [
        "aibattery_alertClaudeAI", "aibattery_alertClaudeCode",
        "aibattery_alert_claudeAI", "aibattery_alert_console",
        "aibattery_alert_claudeAPI", "aibattery_alert_claudeCode",
        "aibattery_alert_claudeForGov",
    ]

    /// Testable migration: consolidates legacy per-component keys into unified alertStatus.
    nonisolated static func migrateAlertKeys(defaults: UserDefaults) {
        let migrationKey = "aibattery_alertKeysMigrated_v2"
        guard !defaults.bool(forKey: migrationKey) else { return }

        let anyEnabled = legacyAlertKeys.contains { defaults.bool(forKey: $0) }
        if anyEnabled {
            defaults.set(true, forKey: UserDefaultsKeys.alertStatus)
        }
        for key in legacyAlertKeys {
            defaults.removeObject(forKey: key)
        }
        defaults.set(true, forKey: migrationKey)
    }

    /// Deliver notification via UNUserNotificationCenter.
    private func deliverNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "aibattery-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                AppLogger.general.warning("Notification delivery failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
