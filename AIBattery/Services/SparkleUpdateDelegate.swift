#if ENABLE_SPARKLE
import AppKit
import Sparkle

/// Delegate that surfaces Sparkle update errors via AppLogger and a published property.
/// Without this, Sparkle fails silently — users see "nothing happens" when an update
/// is available but download/verification/installation fails.
@MainActor
final class SparkleUpdateDelegate: NSObject, SPUUpdaterDelegate {
    /// Last error from Sparkle, surfaced for UI display.
    private(set) var lastError: String?

    /// Called when the update cycle finishes — clears or sets error state.
    /// Reverts activation policy since the Sparkle dialog is done.
    nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        if let error {
            let message = error.localizedDescription
            AppLogger.network.error("Sparkle update failed: \(message)")
            Task { @MainActor in
                self.lastError = message
                NSApp.setActivationPolicy(.accessory)
            }
        } else {
            AppLogger.network.info("Sparkle update cycle completed successfully")
            Task { @MainActor in
                self.lastError = nil
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    /// Called when a started update is aborted.
    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        AppLogger.network.error("Sparkle update aborted: \(error.localizedDescription)")
        Task { @MainActor in
            self.lastError = error.localizedDescription
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Clear the last error (e.g., when user dismisses the message).
    func clearError() {
        lastError = nil
    }
}
#endif
