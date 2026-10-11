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
            UserDefaultsKeys.chartMode,
            UserDefaultsKeys.plan,
            UserDefaultsKeys.accounts,
            UserDefaultsKeys.activeAccountId,
            UserDefaultsKeys.launchAtLogin,
            UserDefaultsKeys.alertStatus,
            UserDefaultsKeys.alertRateLimit,
            UserDefaultsKeys.rateLimitThreshold,
            UserDefaultsKeys.lastUpdateCheck,
            UserDefaultsKeys.lastUpdateVersion,
            UserDefaultsKeys.lastUpdateURL,
            UserDefaultsKeys.autoMetricMode,
            UserDefaultsKeys.colorblindMode,
            UserDefaultsKeys.hasSeenTutorial,
            UserDefaultsKeys.idleSessionMinutes,
            UserDefaultsKeys.throttleTimestamps,
            UserDefaultsKeys.contextCollapsed,
            UserDefaultsKeys.activityCollapsed,
            UserDefaultsKeys.projectsCollapsed,
            UserDefaultsKeys.tokenExpiresAtPrefix,
            UserDefaultsKeys.showAllAccountsInMenuBar,
            UserDefaultsKeys.showFullAccountIdentity,
            UserDefaultsKeys.signedOutProvider,
            UserDefaultsKeys.planTier,
        ]
    }

    /// Persisted preference names are a contract with existing installs: renaming one
    /// silently resets the user's choice on upgrade. Pin the v3.0 additions.
    @Test func v3Keys_areStable() {
        #expect(UserDefaultsKeys.showFullAccountIdentity == "aibattery_showFullAccountIdentity")
        #expect(UserDefaultsKeys.signedOutProvider == "aibattery_signedOutProvider")
        #expect(UserDefaultsKeys.showAllAccountsInMenuBar == "aibattery_showAllAccountsInMenuBar")
    }
}
