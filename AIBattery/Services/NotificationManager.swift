import Foundation
import os
import UserNotifications

/// Fires macOS notifications for status-page outages (Claude.ai / Claude Code).
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

    private init() {}

    // MARK: - Public

    /// Fire test notifications to verify alerts work. Ignores toggle state.
    func testAlerts() {
        hasFired.remove("claudeAPI")
        hasFired.remove("claudeCode")
        checkComponentStatus(key: "claudeAPI", label: "Claude.ai", indicator: .majorOutage)
        checkComponentStatus(key: "claudeCode", label: "Claude Code", indicator: .partialOutage)
    }

    /// Check status page and fire alerts for Claude.ai / Claude Code outages.
    func checkStatusAlerts(status: ClaudeSystemStatus) {
        let alertAI = UserDefaults.standard.bool(forKey: UserDefaultsKeys.alertClaudeAI)
        let alertCode = UserDefaults.standard.bool(forKey: UserDefaultsKeys.alertClaudeCode)

        if alertAI {
            checkComponentStatus(key: "claudeAPI", label: "Claude.ai", indicator: status.claudeAPIStatus)
        }
        if alertCode {
            checkComponentStatus(key: "claudeCode", label: "Claude Code", indicator: status.claudeCodeStatus)
        }
    }

    /// Check rate limits and fire alert when usage crosses the configured threshold.
    /// Deduplicates per window: fires once when crossing, resets when dropping below.
    func checkRateLimitAlerts(rateLimits: RateLimitUsage) {
        let enabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.alertRateLimit)
        guard enabled else { return }

        let threshold = UserDefaults.standard.double(forKey: UserDefaultsKeys.rateLimitThreshold)
        let effectiveThreshold = threshold > 0 ? threshold : 80.0

        checkRateLimitWindow(
            key: "rateLimit5h",
            label: "5-Hour",
            percent: rateLimits.fiveHourPercent,
            threshold: effectiveThreshold
        )
        checkRateLimitWindow(
            key: "rateLimit7d",
            label: "7-Day",
            percent: rateLimits.sevenDayPercent,
            threshold: effectiveThreshold
        )
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
