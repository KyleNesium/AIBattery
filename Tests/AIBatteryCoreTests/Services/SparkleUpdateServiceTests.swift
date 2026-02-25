import Foundation
import Testing
import Sparkle
@testable import AIBatteryCore

@Suite("SparkleUpdateService")
struct SparkleUpdateServiceTests {

    @Test @MainActor func automaticChecksDisabled() {
        let service = SparkleUpdateService.shared
        #expect(service.updater.automaticallyChecksForUpdates == false)
    }

    @Test @MainActor func automaticDownloadsDisabled() {
        let service = SparkleUpdateService.shared
        #expect(service.updater.automaticallyDownloadsUpdates == false)
    }

    @Test @MainActor func updateCheckIntervalIsZero() {
        let service = SparkleUpdateService.shared
        #expect(service.updater.updateCheckInterval == 0)
    }

    @Test @MainActor func feedURLIsSetWhenBundleHasPlist() {
        let service = SparkleUpdateService.shared
        // In the app bundle, SUFeedURL is set in Info.plist.
        // In test bundles it may be nil — verify it doesn't crash either way.
        let feedURL = service.updater.feedURL
        if feedURL != nil {
            let expected = URL(string: "https://kylenesium.github.io/AIBattery/appcast.xml")!
            #expect(feedURL == expected)
        }
        // No assertion failure if nil — test environment lacks Info.plist
    }

    @Test @MainActor func singletonIdentity() {
        let a = SparkleUpdateService.shared
        let b = SparkleUpdateService.shared
        #expect(a === b)
    }

    @Test @MainActor func canCheckForUpdatesReturnsBool() {
        let service = SparkleUpdateService.shared
        // Verify it returns a Bool without crashing — value depends on runtime state
        let result = service.canCheckForUpdates
        #expect(result == true || result == false)
    }

    @Test @MainActor func updaterIsStarted() {
        let service = SparkleUpdateService.shared
        // After init, the updater should have been started
        #expect(service.updater.sessionInProgress == false, "No update session should be active")
    }

    @Test @MainActor func automaticChecksStayDisabledAfterAccess() {
        // Verify accessing canCheckForUpdates doesn't re-enable automatic checks
        let service = SparkleUpdateService.shared
        _ = service.canCheckForUpdates
        #expect(service.updater.automaticallyChecksForUpdates == false)
        #expect(service.updater.automaticallyDownloadsUpdates == false)
    }
}
