import Testing
import Foundation
@testable import AIBatteryCore

@Suite("SettingsManager")
struct SettingsManagerTests {

    @Test func exportSettings_returnsValidJSON() {
        let data = try #require(SettingsManager.exportSettings())
        let json = try? JSONSerialization.jsonObject(with: data)
        #expect(json != nil)
        #expect(json is [String: Any])
    }

    @Test func roundTrip_preservesValues() throws {
        // Set a known value
        let testKey = UserDefaultsKeys.refreshInterval
        let original = UserDefaults.standard.double(forKey: testKey)
        UserDefaults.standard.set(42.0, forKey: testKey)
        defer { UserDefaults.standard.set(original, forKey: testKey) }

        // Export
        let data = try #require(SettingsManager.exportSettings())

        // Change value
        UserDefaults.standard.set(99.0, forKey: testKey)
        #expect(UserDefaults.standard.double(forKey: testKey) == 99.0)

        // Import
        try SettingsManager.importSettings(from: data)
        #expect(UserDefaults.standard.double(forKey: testKey) == 42.0)
    }

    @Test func importSettings_invalidJSON_throws() {
        let badData = "not json".data(using: .utf8)!
        #expect(throws: Error.self) {
            try SettingsManager.importSettings(from: badData)
        }
    }

    @Test func importSettings_ignoresUnknownKeys() throws {
        let json = #"{"unknown_key_xyz": "value", "aibattery_refreshInterval": 30}"#
        let data = json.data(using: .utf8)!
        try SettingsManager.importSettings(from: data)
        #expect(UserDefaults.standard.object(forKey: "unknown_key_xyz") == nil)
    }

    @Test func exportableKeys_areNonEmpty() {
        #expect(!SettingsManager.exportableKeys.isEmpty)
    }

    @Test func exportableKeys_excludesSensitive() {
        let keys = Set(SettingsManager.exportableKeys)
        #expect(!keys.contains(UserDefaultsKeys.accounts))
        #expect(!keys.contains(UserDefaultsKeys.activeAccountId))
        #expect(!keys.contains(UserDefaultsKeys.lastUpdateCheck))
        #expect(!keys.contains(UserDefaultsKeys.skipVersion))
    }
}
