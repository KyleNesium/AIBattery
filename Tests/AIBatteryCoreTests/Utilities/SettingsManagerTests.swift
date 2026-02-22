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

    @Test func exportSettings_includesAllKeys() throws {
        let data = try #require(SettingsManager.exportSettings())
        let dict = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        // Every exportable key should appear (defaults fill in unset keys)
        for key in SettingsManager.exportableDefaults.keys {
            #expect(dict[key] != nil, "Missing key: \(key)")
        }
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

    @Test func importSettings_noRecognizedKeys_throws() {
        let json = #"{"totally_unknown": true}"#
        let data = json.data(using: .utf8)!
        #expect(throws: Error.self) {
            try SettingsManager.importSettings(from: data)
        }
    }

    @Test func exportableDefaults_areNonEmpty() {
        #expect(!SettingsManager.exportableDefaults.isEmpty)
    }

    @Test func exportableDefaults_excludesSensitive() {
        let keys = Set(SettingsManager.exportableDefaults.keys)
        #expect(!keys.contains(UserDefaultsKeys.accounts))
        #expect(!keys.contains(UserDefaultsKeys.activeAccountId))
        #expect(!keys.contains(UserDefaultsKeys.lastUpdateCheck))
        #expect(!keys.contains(UserDefaultsKeys.skipVersion))
        #expect(!keys.contains(UserDefaultsKeys.hasSeenTutorial))
    }

    @Test func exportableDefaults_allKeysHavePrefix() {
        for key in SettingsManager.exportableDefaults.keys {
            #expect(key.hasPrefix("aibattery_"), "Key '\(key)' missing prefix")
        }
    }

    @Test func importSettings_emptyDict_throws() {
        let json = #"{}"#
        let data = json.data(using: .utf8)!
        #expect(throws: Error.self) {
            try SettingsManager.importSettings(from: data)
        }
    }

    @Test func importSettings_arrayJSON_throws() {
        let json = #"[1, 2, 3]"#
        let data = json.data(using: .utf8)!
        #expect(throws: Error.self) {
            try SettingsManager.importSettings(from: data)
        }
    }

    @Test func roundTrip_preservesBooleans() throws {
        let key = UserDefaultsKeys.colorblindMode
        let original = UserDefaults.standard.bool(forKey: key)
        UserDefaults.standard.set(true, forKey: key)
        defer { UserDefaults.standard.set(original, forKey: key) }

        let data = try #require(SettingsManager.exportSettings())

        UserDefaults.standard.set(false, forKey: key)
        #expect(UserDefaults.standard.bool(forKey: key) == false)

        try SettingsManager.importSettings(from: data)
        #expect(UserDefaults.standard.bool(forKey: key) == true)
    }

    @Test func roundTrip_preservesStrings() throws {
        let key = UserDefaultsKeys.metricMode
        let original = UserDefaults.standard.string(forKey: key)
        UserDefaults.standard.set("ctx", forKey: key)
        defer {
            if let original { UserDefaults.standard.set(original, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        let data = try #require(SettingsManager.exportSettings())

        UserDefaults.standard.set("5h", forKey: key)
        try SettingsManager.importSettings(from: data)
        #expect(UserDefaults.standard.string(forKey: key) == "ctx")
    }
}
