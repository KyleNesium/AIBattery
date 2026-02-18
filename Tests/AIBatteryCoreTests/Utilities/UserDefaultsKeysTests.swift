import Testing
@testable import AIBatteryCore

@Suite("UserDefaultsKeys")
struct UserDefaultsKeysTests {

    /// All keys must use the "aibattery_" prefix for namespacing.
    @Test func allKeys_havePrefix() {
        let keys = [
            UserDefaultsKeys.metricMode,
            UserDefaultsKeys.orgName,
            UserDefaultsKeys.displayName,
            UserDefaultsKeys.refreshInterval,
            UserDefaultsKeys.tokenWindowDays,
            UserDefaultsKeys.alertClaudeAI,
            UserDefaultsKeys.alertClaudeCode,
            UserDefaultsKeys.chartMode,
            UserDefaultsKeys.plan,
        ]
        for key in keys {
            #expect(key.hasPrefix("aibattery_"), "Key '\(key)' missing 'aibattery_' prefix")
        }
    }

    /// No two keys should share the same value.
    @Test func allKeys_areUnique() {
        let keys = [
            UserDefaultsKeys.metricMode,
            UserDefaultsKeys.orgName,
            UserDefaultsKeys.displayName,
            UserDefaultsKeys.refreshInterval,
            UserDefaultsKeys.tokenWindowDays,
            UserDefaultsKeys.alertClaudeAI,
            UserDefaultsKeys.alertClaudeCode,
            UserDefaultsKeys.chartMode,
            UserDefaultsKeys.plan,
        ]
        let unique = Set(keys)
        #expect(unique.count == keys.count, "Duplicate UserDefaults key detected")
    }
}
