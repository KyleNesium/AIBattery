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

    @Test @MainActor func feedURLMatchesInfoPlist() {
        let service = SparkleUpdateService.shared
        let expectedURL = URL(string: "https://kylenesium.github.io/AIBattery/appcast.xml")!
        // Feed URL comes from Info.plist SUFeedURL — in tests it may be nil (no bundle),
        // but the setter/getter path should not crash
        if let feedURL = service.updater.feedURL {
            #expect(feedURL == expectedURL)
        }
    }

    @Test @MainActor func singletonIdentity() {
        let a = SparkleUpdateService.shared
        let b = SparkleUpdateService.shared
        #expect(a === b)
    }

    @Test @MainActor func canCheckForUpdatesReturnsWithoutCrash() {
        let service = SparkleUpdateService.shared
        // Just verify it returns a Bool without crashing
        _ = service.canCheckForUpdates
    }
}
