import Foundation
import Testing
@testable import AIBatteryCore

@Suite("AccountIdentityRegistry")
@MainActor
struct AccountIdentityRegistryTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "AccountIdentityRegistryTests-\(UUID().uuidString)")!
    }

    @Test func migrate_movesEveryRegisteredKey() {
        let defaults = makeDefaults()
        for key in AccountIdentityRegistry.keys(for: "pending-1") {
            defaults.set("value-for-\(key)", forKey: key)
        }
        AccountIdentityRegistry.migrate(from: "pending-1", to: "org-1", defaults: defaults)

        for key in AccountIdentityRegistry.keys(for: "pending-1") {
            #expect(defaults.object(forKey: key) == nil, "\(key) must not orphan under the dead id")
        }
        for key in AccountIdentityRegistry.keys(for: "org-1") {
            #expect(defaults.object(forKey: key) != nil, "\(key) must follow the account")
        }
    }

    /// Calibration is the one that bites: without it a resolved account shows no
    /// percentage until a poll happens to land in the 20–80% band again.
    @Test func migrate_carriesCalibration() {
        let defaults = makeDefaults()
        defaults.set(88_000, forKey: "aibattery_calibrated_5h_limit_pending-2")
        AccountIdentityRegistry.migrate(from: "pending-2", to: "org-2", defaults: defaults)
        #expect(defaults.integer(forKey: "aibattery_calibrated_5h_limit_org-2") == 88_000)
        #expect(defaults.object(forKey: "aibattery_calibrated_5h_limit_pending-2") == nil)
    }

    @Test func migrate_destinationWinsButSourceIsStillCleared() {
        let defaults = makeDefaults()
        let base = "aibattery_calibrated_at"
        defaults.set(1, forKey: "\(base)_pending-3")
        defaults.set(2, forKey: "\(base)_org-3")
        AccountIdentityRegistry.migrate(from: "pending-3", to: "org-3", defaults: defaults)
        #expect(defaults.integer(forKey: "\(base)_org-3") == 2)
        #expect(defaults.object(forKey: "\(base)_pending-3") == nil)
    }

    @Test func migrate_isANoOpForTheSameOrAnEmptyId() {
        let defaults = makeDefaults()
        defaults.set(5, forKey: "aibattery_calibrated_at_org-4")
        AccountIdentityRegistry.migrate(from: "org-4", to: "org-4", defaults: defaults)
        AccountIdentityRegistry.migrate(from: "", to: "org-4", defaults: defaults)
        #expect(defaults.integer(forKey: "aibattery_calibrated_at_org-4") == 5)
    }

    /// The rate-limit blob migrates through `RateLimitFetcher.migrate`, which also moves
    /// the in-memory cache. Listing it here too would move it twice.
    @Test func registry_doesNotOwnTheRateLimitBlob() {
        #expect(!AccountIdentityRegistry.prefixes.contains(RateLimitFetcher.persistKeyPrefix))
    }
}
