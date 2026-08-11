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
        Self.configure(updaterController.updater)
        updaterController.startUpdater()
    }

    /// The one place update-check policy is set — user-initiated checks only.
    static func configure(_ updater: SPUUpdater) {
        updater.automaticallyChecksForUpdates = false
        updater.automaticallyDownloadsUpdates = false
        updater.updateCheckInterval = 0
    }

    /// Testable init: accepts a controller and applies the same configuration as the
    /// app path, but NEVER calls `startUpdater()`. Tests must use this instead of
    /// `.shared` — starting a real Sparkle updater inside the test runner makes
    /// Sparkle's standard user driver raise a modal NSAlert when its host-bundle
    /// validation or update check fails there, freezing the main thread (and with it
    /// every @MainActor test) until the dialog is dismissed. That modal was the
    /// intermittent full-suite hang on loaded local runs and the headless CI runner.
    init(controller: SPUStandardUpdaterController) {
        updaterController = controller
        Self.configure(controller.updater)
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
