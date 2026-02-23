import Testing
@testable import AIBatteryCore

@Suite("UserDefaultsKeys")
struct UserDefaultsKeysTests {

    /// All keys must use the "aibattery_" prefix for namespacing.
    @Test func allKeys_havePrefix() {
        let keys = allKeys
        for key in keys {
            #expect(key.hasPrefix("aibattery_"), "Key '\(key)' missing 'aibattery_' prefix")
        }
    }

    /// No two keys should share the same value.
    @Test func allKeys_areUnique() {
        let keys = allKeys
        let unique = Set(keys)
        #expect(unique.count == keys.count, "Duplicate UserDefaults key detected")
    }

    // MARK: - Helpers

    private var allKeys: [String] {
        [
            UserDefaultsKeys.metricMode,
            UserDefaultsKeys.refreshInterval,
            UserDefaultsKeys.tokenWindowDays,
            UserDefaultsKeys.alertClaudeAI,
            UserDefaultsKeys.alertClaudeCode,
            UserDefaultsKeys.chartMode,
            UserDefaultsKeys.plan,
            UserDefaultsKeys.accounts,
            UserDefaultsKeys.activeAccountId,
            UserDefaultsKeys.launchAtLogin,
            UserDefaultsKeys.alertRateLimit,
            UserDefaultsKeys.rateLimitThreshold,
            UserDefaultsKeys.showCostEstimate,
            UserDefaultsKeys.showTokens,
            UserDefaultsKeys.showActivity,
            UserDefaultsKeys.lastUpdateCheck,
            UserDefaultsKeys.lastUpdateVersion,
            UserDefaultsKeys.lastUpdateURL,
            UserDefaultsKeys.autoMetricMode,
            UserDefaultsKeys.colorblindMode,
            UserDefaultsKeys.hasSeenTutorial,
        ]
    }
}
