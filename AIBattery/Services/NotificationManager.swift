import Foundation
import os

/// Fires macOS notifications for status-page outages (Claude.ai / Claude Code).
/// Uses osascript for reliable delivery from unsigned/SPM-built menu bar apps.
/// Deduplicates: only fires once per outage, resets when service recovers.
public final class NotificationManager {
    public static let shared = NotificationManager()

    /// Tracks whether we already fired for each key while condition was active.
    private var hasFired: [String: Bool] = [:]

    /// Pending alerts queued for batching (flushed after 500ms).
    private var pendingAlerts: [(title: String, body: String)] = []
    private var flushTimer: DispatchSourceTimer?
    private let flushQueue = DispatchQueue(label: "com.KyleNesium.AIBattery.notifications")
    private static let batchDelay: TimeInterval = 0.5

    private init() {}

    // MARK: - Public

    /// Fire test notifications to verify alerts work. Ignores toggle state.
    func testAlerts() {
        hasFired["claudeAPI"] = false
        hasFired["claudeCode"] = false
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
    static func shouldAlert(percent: Double, threshold: Double, previouslyFired: Bool) -> Bool {
        percent >= threshold && !previouslyFired
    }

    /// No-op kept for call-site compatibility (osascript needs no permission).
    func requestPermission() {}

    // MARK: - Private

    private func checkRateLimitWindow(key: String, label: String, percent: Double, threshold: Double) {
        if Self.shouldAlert(percent: percent, threshold: threshold, previouslyFired: hasFired[key] == true) {
            hasFired[key] = true
            send(
                title: "AI Battery: \(label) rate limit",
                body: "\(label) usage at \(Int(percent))% (threshold: \(Int(threshold))%)."
            )
        } else if percent < threshold {
            hasFired[key] = false
        }
    }

    private func checkComponentStatus(key: String, label: String, indicator: StatusIndicator) {
        let isDown = indicator != .operational && indicator != .unknown
        if isDown {
            if hasFired[key] != true {
                hasFired[key] = true
                let statusText = indicator.displayName
                send(
                    title: "AI Battery: \(label) is down",
                    body: "\(label) status: \(statusText)."
                )
            }
        } else {
            hasFired[key] = false
        }
    }

    /// Queue a notification for batched delivery.
    /// If multiple alerts arrive within 500ms, they are combined into a single notification.
    private func send(title: String, body: String) {
        flushQueue.async { [weak self] in
            guard let self else { return }
            self.pendingAlerts.append((title: title, body: body))

            // Start or restart the flush timer
            self.flushTimer?.cancel()
            let timer = DispatchSource.makeTimerSource(queue: self.flushQueue)
            timer.schedule(deadline: .now() + Self.batchDelay)
            timer.setEventHandler { [weak self] in
                self?.flushPendingAlerts()
            }
            timer.resume()
            self.flushTimer = timer
        }
    }

    /// Flush pending alerts — single alert sent as-is, multiple combined.
    private func flushPendingAlerts() {
        let alerts = pendingAlerts
        pendingAlerts.removeAll()
        flushTimer?.cancel()
        flushTimer = nil

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

    /// Deliver notification via osascript — works reliably for unsigned menu bar apps.
    /// Process.arguments bypasses the shell (uses execve directly), so shell metacharacters
    /// like $ and ` are safe. We only need to escape AppleScript string delimiters.
    private func deliverNotification(title: String, body: String) {
        let script = "display notification \(applescriptQuoted(body)) with title \(applescriptQuoted(title)) sound name \"default\""
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        do {
            try proc.run()
            // Reap the child process on a background queue to prevent zombies
            DispatchQueue.global(qos: .utility).async {
                proc.waitUntilExit()
            }
        } catch {
            AppLogger.general.warning("osascript notification failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Safely quote a string for embedding in AppleScript.
    /// Escapes backslashes and double quotes (the only special chars inside AppleScript strings).
    private func applescriptQuoted(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
