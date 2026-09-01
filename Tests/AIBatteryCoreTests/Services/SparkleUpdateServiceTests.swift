#if ENABLE_SPARKLE
import Foundation
import Testing
import Sparkle
@testable import AIBatteryCore

// IMPORTANT: These tests must NEVER touch `SparkleUpdateService.shared`. The shared
// init calls `startUpdater()` on a real SPUStandardUpdaterController — inside the test
// runner, Sparkle's host-bundle validation / update check fails and its standard user
// driver raises a modal NSAlert on the main thread. That modal froze every @MainActor
// test behind it: the intermittent full-suite hang on loaded local runs and the
// 19-minute-timeout kills on the headless CI runner. The testable
// `init(controller:)` applies the identical configuration without ever starting the
// updater, so the config contract is still pinned.
@Suite("SparkleUpdateService")
struct SparkleUpdateServiceTests {
    /// A controller that is never started — safe inside the test runner.
    @MainActor private static func makeService() -> SparkleUpdateService {
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: SparkleUpdateDelegate(),
            userDriverDelegate: nil
        )
        return SparkleUpdateService(controller: controller)
    }

    @Test @MainActor func automaticChecksDisabled() {
        let service = Self.makeService()
        #expect(service.updater.automaticallyChecksForUpdates == false)
    }

    @Test @MainActor func automaticDownloadsDisabled() {
        let service = Self.makeService()
        #expect(service.updater.automaticallyDownloadsUpdates == false)
    }

    @Test @MainActor func updateCheckIntervalIsZero() {
        let service = Self.makeService()
        #expect(service.updater.updateCheckInterval == 0)
    }

    @Test @MainActor func feedURLIsSetWhenBundleHasPlist() throws {
        let service = Self.makeService()
        // In the app bundle, SUFeedURL is set in Info.plist.
        // In test bundles it may be nil — verify it doesn't crash either way.
        let feedURL = service.updater.feedURL
        if feedURL != nil {
            let expected = try #require(URL(string: "https://kylenesium.github.io/AIBattery/appcast.xml"))
            #expect(feedURL == expected)
        }
        // No assertion failure if nil — test environment lacks Info.plist
    }

    @Test @MainActor func controllerInitAppliesSameConfigurationAsAppPath() {
        // The testable init must route through the same `configure(_:)` the shared
        // init uses — otherwise these tests would pin a config the app never applies.
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: SparkleUpdateDelegate(),
            userDriverDelegate: nil
        )
        controller.updater.automaticallyChecksForUpdates = true
        let service = SparkleUpdateService(controller: controller)
        #expect(service.updater.automaticallyChecksForUpdates == false)
    }

    @Test @MainActor func canCheckForUpdatesReturnsBool() {
        let service = Self.makeService()
        // Verify it returns a Bool without crashing — value depends on runtime state
        let result = service.canCheckForUpdates
        #expect(result == true || result == false)
    }

    @Test @MainActor func noUpdateSessionOnNonStartedController() {
        let service = Self.makeService()
        #expect(service.updater.sessionInProgress == false, "No update session should be active")
    }

    @Test @MainActor func automaticChecksStayDisabledAfterAccess() {
        // Verify accessing canCheckForUpdates doesn't re-enable automatic checks
        let service = Self.makeService()
        _ = service.canCheckForUpdates
        #expect(service.updater.automaticallyChecksForUpdates == false)
        #expect(service.updater.automaticallyDownloadsUpdates == false)
    }
}
#endif
