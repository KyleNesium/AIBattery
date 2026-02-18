import Foundation

/// Fires macOS notifications for status-page outages (Claude.ai / Claude Code).
/// Uses osascript for reliable delivery from unsigned/SPM-built menu bar apps.
/// Deduplicates: only fires once per outage, resets when service recovers.
public final class NotificationManager {
    public static let shared = NotificationManager()

    /// Tracks whether we already fired for each key while condition was active.
    private var hasFired: [String: Bool] = [:]

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

    /// No-op kept for call-site compatibility (osascript needs no permission).
    func requestPermission() {}

    // MARK: - Private

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

    /// Deliver notification via osascript — works reliably for unsigned menu bar apps.
    private func send(title: String, body: String) {
        let escaped = { (s: String) -> String in
            s.replacingOccurrences(of: "\\", with: "\\\\")
             .replacingOccurrences(of: "\"", with: "\\\"")
        }
        let script = "display notification \"\(escaped(body))\" with title \"\(escaped(title))\" sound name \"default\""
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        try? proc.run()
    }
}
