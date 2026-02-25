import AppKit
import Sparkle

/// Thin wrapper around Sparkle's `SPUStandardUpdaterController` for user-initiated updates.
/// Disables all automatic behavior — Sparkle only activates when the user clicks "Update".
@MainActor
public final class SparkleUpdateService {
    public static let shared = SparkleUpdateService()

    private let updaterController: SPUStandardUpdaterController

    private init() {
        // startingUpdater: false — we configure settings before starting
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        let updater = updaterController.updater
        updater.automaticallyChecksForUpdates = false
        updater.automaticallyDownloadsUpdates = false
        updater.updateCheckInterval = 0

        updaterController.startUpdater()
    }

    /// Testable init that accepts a pre-configured controller.
    init(controller: SPUStandardUpdaterController) {
        updaterController = controller
    }

    /// Whether Sparkle is ready to check for updates.
    public var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }

    /// Trigger the Sparkle update flow. Brings the app to front first
    /// (required for LSUIElement menu bar apps so the dialog appears in front).
    public func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        updaterController.checkForUpdates(nil)
    }

    /// Exposes the underlying updater for testing configuration.
    var updater: SPUUpdater {
        updaterController.updater
    }
}
