import Foundation
import AppKit

/// Export and import user preferences as JSON.
///
/// Excludes volatile/security-sensitive keys (accounts, tokens, update state).
enum SettingsManager {
    /// Keys safe to export/import with their default values.
    /// Defaults match the @AppStorage declarations in the views.
    static let exportableDefaults: [String: Any] = [
        UserDefaultsKeys.metricMode: "5h",
        UserDefaultsKeys.refreshInterval: 60.0,
        UserDefaultsKeys.tokenWindowDays: 0.0,
        UserDefaultsKeys.alertClaudeAI: false,
        UserDefaultsKeys.alertClaudeCode: false,
        UserDefaultsKeys.alertRateLimit: false,
        UserDefaultsKeys.rateLimitThreshold: 80.0,
        UserDefaultsKeys.chartMode: "24H",
        UserDefaultsKeys.showCostEstimate: false,
        UserDefaultsKeys.showTokens: true,
        UserDefaultsKeys.showActivity: true,
        UserDefaultsKeys.launchAtLogin: false,
        UserDefaultsKeys.colorblindMode: false,
    ]

    /// Export current settings as JSON data. Returns nil if serialization fails.
    static func exportSettings() -> Data? {
        var dict: [String: Any] = [:]
        for (key, defaultValue) in exportableDefaults {
            dict[key] = UserDefaults.standard.object(forKey: key) ?? defaultValue
        }
        return try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
    }

    /// Import settings from JSON data. Only known keys are applied.
    static func importSettings(from data: Data) throws {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SettingsError.invalidFormat
        }

        let knownKeys = Set(exportableDefaults.keys)
        var applied = 0
        for (key, value) in dict {
            guard knownKeys.contains(key) else { continue }
            UserDefaults.standard.set(value, forKey: key)
            applied += 1
        }

        guard applied > 0 else {
            throw SettingsError.noKeysApplied
        }
    }

    /// Copy settings JSON to clipboard. Returns true on success.
    @discardableResult
    static func exportToClipboard() -> Bool {
        guard let data = exportSettings(),
              let json = String(data: data, encoding: .utf8) else { return false }
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(json, forType: .string)
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
        case noKeysApplied

        var errorDescription: String? {
            switch self {
            case .invalidFormat: return "Invalid settings format. Expected JSON."
            case .emptyClipboard: return "Clipboard is empty or doesn't contain text."
            case .noKeysApplied: return "No recognized settings found in JSON."
            }
        }
    }
}
