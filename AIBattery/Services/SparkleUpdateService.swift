#if ENABLE_SPARKLE
import AppKit
import Sparkle

/// Thin wrapper around Sparkle's `SPUStandardUpdaterController` for user-initiated updates.
/// Disables all automatic behavior — Sparkle only activates when the user clicks "Update".
@MainActor
public final class SparkleUpdateService {
    public static let shared = SparkleUpdateService()

    private let updaterController: SPUStandardUpdaterController
    let delegate = SparkleUpdateDelegate()

    private init() {
        // startingUpdater: false — we configure settings before starting
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: delegate,
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

    /// Last error from Sparkle, if any.
    public var lastError: String? { delegate.lastError }

    /// Clear the Sparkle error state.
    public func clearError() {
        delegate.clearError()
    }

    /// Trigger the Sparkle update flow. Temporarily becomes a regular app
    /// so Sparkle's dialog appears in front (LSUIElement apps have no dock presence).
    /// Activation policy reverts via the delegate's didFinishUpdateCycleFor callback,
    /// with a 60-second safety timeout as fallback.
    public func checkForUpdates() {
        delegate.clearError()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        updaterController.checkForUpdates(nil)

        // Safety timeout — delegate normally reverts policy, but guard against
        // cases where the callback doesn't fire (e.g., user dismisses immediately).
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            if NSApp.activationPolicy() == .regular {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    /// Exposes the underlying updater for testing configuration.
    var updater: SPUUpdater {
        updaterController.updater
    }
}
#endif
