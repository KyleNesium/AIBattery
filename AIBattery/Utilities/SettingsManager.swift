import Foundation
import AppKit

/// Export and import user preferences as JSON.
///
/// Excludes volatile/security-sensitive keys (accounts, tokens, update state).
enum SettingsManager {
    /// Keys safe to export/import — matches all user-configurable preferences.
    static let exportableKeys: [String] = [
        UserDefaultsKeys.metricMode,
        UserDefaultsKeys.refreshInterval,
        UserDefaultsKeys.tokenWindowDays,
        UserDefaultsKeys.alertClaudeAI,
        UserDefaultsKeys.alertClaudeCode,
        UserDefaultsKeys.alertRateLimit,
        UserDefaultsKeys.rateLimitThreshold,
        UserDefaultsKeys.chartMode,
        UserDefaultsKeys.showCostEstimate,
        UserDefaultsKeys.showTokens,
        UserDefaultsKeys.showActivity,
        UserDefaultsKeys.launchAtLogin,
        UserDefaultsKeys.menuBarDecimal,
        UserDefaultsKeys.compactBars,
        UserDefaultsKeys.colorblindMode,
    ]

    /// Export current settings as JSON data.
    static func exportSettings() -> Data {
        var dict: [String: Any] = [:]
        for key in exportableKeys {
            if let value = UserDefaults.standard.object(forKey: key) {
                dict[key] = value
            }
        }
        // swiftlint:disable:next force_try
        return try! JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
    }

    /// Import settings from JSON data. Only known keys are applied.
    static func importSettings(from data: Data) throws {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SettingsError.invalidFormat
        }

        let knownKeys = Set(exportableKeys)
        for (key, value) in dict {
            guard knownKeys.contains(key) else { continue }
            UserDefaults.standard.set(value, forKey: key)
        }
    }

    /// Copy settings JSON to clipboard.
    static func exportToClipboard() {
        let data = exportSettings()
        if let json = String(data: data, encoding: .utf8) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(json, forType: .string)
        }
    }

    /// Import settings from clipboard JSON.
    static func importFromClipboard() throws {
        guard let json = NSPasteboard.general.string(forType: .string),
              let data = json.data(using: .utf8) else {
            throw SettingsError.emptyClipboard
        }
        try importSettings(from: data)
    }

    enum SettingsError: Error, LocalizedError {
        case invalidFormat
        case emptyClipboard

        var errorDescription: String? {
            switch self {
            case .invalidFormat: return "Invalid settings format. Expected JSON."
            case .emptyClipboard: return "Clipboard is empty or doesn't contain text."
            }
        }
    }
}
