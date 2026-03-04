import Foundation
import Testing
@testable import AIBatteryCore

@Suite("NotificationManager")
struct NotificationManagerTests {

    @Test func shouldAlert_aboveThreshold_notPreviouslyFired() {
        #expect(NotificationManager.shouldAlert(percent: 85, threshold: 80, previouslyFired: false))
    }

    @Test func shouldAlert_exactlyAtThreshold() {
        #expect(NotificationManager.shouldAlert(percent: 80, threshold: 80, previouslyFired: false))
    }

    @Test func shouldAlert_belowThreshold() {
        #expect(!NotificationManager.shouldAlert(percent: 79, threshold: 80, previouslyFired: false))
    }

    @Test func shouldAlert_aboveThreshold_previouslyFired() {
        #expect(!NotificationManager.shouldAlert(percent: 90, threshold: 80, previouslyFired: true))
    }

    @Test func shouldAlert_zeroPercent() {
        #expect(!NotificationManager.shouldAlert(percent: 0, threshold: 80, previouslyFired: false))
    }

    @Test func shouldAlert_hundredPercent_notFired() {
        #expect(NotificationManager.shouldAlert(percent: 100, threshold: 80, previouslyFired: false))
    }

    @Test func shouldAlert_customThreshold_50() {
        #expect(NotificationManager.shouldAlert(percent: 50, threshold: 50, previouslyFired: false))
        #expect(!NotificationManager.shouldAlert(percent: 49, threshold: 50, previouslyFired: false))
    }

    @Test func shouldAlert_customThreshold_95() {
        #expect(!NotificationManager.shouldAlert(percent: 94, threshold: 95, previouslyFired: false))
        #expect(NotificationManager.shouldAlert(percent: 95, threshold: 95, previouslyFired: false))
    }

    // MARK: - Extended edge cases

    @Test func shouldAlert_fractionalPercent_justBelow() {
        #expect(!NotificationManager.shouldAlert(percent: 79.9, threshold: 80, previouslyFired: false))
    }

    @Test func shouldAlert_fractionalPercent_justAbove() {
        #expect(NotificationManager.shouldAlert(percent: 80.1, threshold: 80, previouslyFired: false))
    }

    @Test func shouldAlert_dropsBelow_thenRisesAgain() {
        #expect(NotificationManager.shouldAlert(percent: 85, threshold: 80, previouslyFired: false))
        #expect(!NotificationManager.shouldAlert(percent: 90, threshold: 80, previouslyFired: true))
        #expect(!NotificationManager.shouldAlert(percent: 70, threshold: 80, previouslyFired: true))
        #expect(NotificationManager.shouldAlert(percent: 85, threshold: 80, previouslyFired: false))
    }

    @Test func shouldAlert_minimumThreshold_50() {
        #expect(!NotificationManager.shouldAlert(percent: 49, threshold: 50, previouslyFired: false))
        #expect(NotificationManager.shouldAlert(percent: 50, threshold: 50, previouslyFired: false))
    }

    @Test func shouldAlert_negativePercent() {
        #expect(!NotificationManager.shouldAlert(percent: -10, threshold: 80, previouslyFired: false))
    }

    // MARK: - Alert key migration

    private func tempDefaults() -> (UserDefaults, String) {
        let name = "test_migrate_\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test func migrateAlertKeys_enablesAlertStatus_whenLegacyKeyEnabled() {
        let (defaults, suite) = tempDefaults()
        defaults.set(true, forKey: "aibattery_alertClaudeCode")
        NotificationManager.migrateAlertKeys(defaults: defaults)
        #expect(defaults.bool(forKey: UserDefaultsKeys.alertStatus))
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func migrateAlertKeys_doesNotEnable_whenNoLegacyKeys() {
        let (defaults, suite) = tempDefaults()
        NotificationManager.migrateAlertKeys(defaults: defaults)
        #expect(!defaults.bool(forKey: UserDefaultsKeys.alertStatus))
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func migrateAlertKeys_removesAllLegacyKeys() {
        let (defaults, suite) = tempDefaults()
        for key in NotificationManager.legacyAlertKeys {
            defaults.set(true, forKey: key)
        }
        NotificationManager.migrateAlertKeys(defaults: defaults)
        for key in NotificationManager.legacyAlertKeys {
            #expect(defaults.object(forKey: key) == nil, "Legacy key \(key) not removed")
        }
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func migrateAlertKeys_skipsWhenAlreadyMigrated() {
        let (defaults, suite) = tempDefaults()
        defaults.set(true, forKey: "aibattery_alertKeysMigrated_v2")
        defaults.set(true, forKey: "aibattery_alertClaudeAI")
        NotificationManager.migrateAlertKeys(defaults: defaults)
        #expect(defaults.bool(forKey: "aibattery_alertClaudeAI"))
        #expect(!defaults.bool(forKey: UserDefaultsKeys.alertStatus))
        defaults.removePersistentDomain(forName: suite)
    }
}
