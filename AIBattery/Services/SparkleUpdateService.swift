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

    /// Trigger the Sparkle update flow. Temporarily becomes a regular app
    /// so Sparkle's dialog appears in front (LSUIElement apps have no dock presence).
    public func checkForUpdates() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        updaterController.checkForUpdates(nil)

        // Revert to accessory (menu bar only) after Sparkle has time to present its dialog
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Exposes the underlying updater for testing configuration.
    var updater: SPUUpdater {
        updaterController.updater
    }
}
