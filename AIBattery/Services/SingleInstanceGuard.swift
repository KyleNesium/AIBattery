import Foundation
import AppKit

/// Ensures only one instance of AIBattery runs at a time.
/// On launch, kills any existing instances sharing the same bundle identifier,
/// preventing the zombie-process buildup that causes macOS launch failures
/// (RBSRequestErrorDomain Code=5).
public enum SingleInstanceGuard {

    /// Call once at startup, before the SwiftUI body is evaluated.
    /// If another AIBattery is already running, sends it SIGTERM first (graceful),
    /// waits briefly, then SIGKILL (forced) if it's still alive.
    public static func ensureSingleInstance() {
        let myPID = ProcessInfo.processInfo.processIdentifier

        let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.KyleNesium.AIBattery"
        )

        for app in running where app.processIdentifier != myPID {
            // Try graceful termination first
            app.terminate()
        }

        // Give 1s for graceful shutdown, then force-kill stragglers
        if running.count > 1 {
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                let stillRunning = NSRunningApplication.runningApplications(
                    withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.KyleNesium.AIBattery"
                )
                for app in stillRunning where app.processIdentifier != myPID {
                    app.forceTerminate()
                }
            }
        }
    }

    /// Registers SIGTERM handler so the app shuts down cleanly when killed.
    /// This prevents zombie processes from accumulating.
    public static func installSignalHandlers() {
        signal(SIGTERM) { _ in
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
