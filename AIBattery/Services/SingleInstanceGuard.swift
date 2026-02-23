import Foundation
import AppKit

/// Ensures only one instance of AIBattery runs at a time.
///
/// Primary mechanism: a POSIX file lock (`flock`) on a well-known lock file.
/// This is atomic and race-free — two processes cannot both acquire the lock.
///
/// Secondary mechanism: sends SIGTERM to any other instances sharing the same
/// bundle identifier, which cleans up zombie processes that may have survived
/// a crash or force-quit (preventing RBSRequestErrorDomain Code=5).
public enum SingleInstanceGuard {

    private static let lockPath = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/aibattery.lock")
        .path

    /// File descriptor for the lock file — kept open for the process lifetime.
    private static var lockFD: Int32 = -1

    /// Call once at startup, before the SwiftUI body is evaluated.
    /// If another instance holds the lock, this process exits immediately.
    public static func ensureSingleInstance() {
        acquireLockOrExit()
        terminateStaleInstances()
    }

    /// Acquires an exclusive file lock. If another instance already holds it,
    /// exits immediately (the other instance is healthy and should keep running).
    private static func acquireLockOrExit() {
        // Ensure parent directory exists
        let dir = (lockPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        lockFD = open(lockPath, O_CREAT | O_RDWR, 0o644)
        guard lockFD >= 0 else {
            // Cannot open lock file — proceed without lock (degrade gracefully)
            return
        }

        // Non-blocking exclusive lock
        if flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
            // Another instance holds the lock — exit silently
            exit(0)
        }

        // Lock acquired — write our PID for diagnostics
        ftruncate(lockFD, 0)
        let pidStr = "\(ProcessInfo.processInfo.processIdentifier)\n"
        _ = pidStr.withCString { write(lockFD, $0, strlen($0)) }
        // Leave lockFD open — the lock is released automatically when the process exits.
    }

    /// Terminates any stale instances that survived a previous crash.
    /// Runs on the main thread since NSRunningApplication is AppKit API.
    private static func terminateStaleInstances() {
        let myPID = ProcessInfo.processInfo.processIdentifier
        let bundleId = Bundle.main.bundleIdentifier ?? "com.KyleNesium.AIBattery"

        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)

        for app in running where app.processIdentifier != myPID {
            app.terminate()
        }

        // Give 1s for graceful shutdown, then force-kill stragglers (on main thread)
        if running.count > 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let stillRunning = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
                for app in stillRunning where app.processIdentifier != myPID {
                    app.forceTerminate()
                }
            }
        }
    }

    /// Checks if the app bundle has macOS quarantine attributes and shows an alert
    /// with fix instructions. Quarantined apps can be silently killed by Gatekeeper.
    public static func checkQuarantine() {
        guard let bundlePath = Bundle.main.bundlePath as NSString? else { return }
        let path = bundlePath as String

        // Check for com.apple.quarantine extended attribute
        let size = getxattr(path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0 else { return }

        // Quarantine detected — show alert
        let alert = NSAlert()
        alert.messageText = "AI Battery is quarantined"
        alert.informativeText = """
            macOS has flagged this app as downloaded from the internet. \
            It may be silently terminated by Gatekeeper.

            To fix, run this in Terminal:
            xattr -cr \(path)

            Then relaunch the app.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Copy Fix Command")
        alert.addButton(withTitle: "Continue Anyway")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("xattr -cr \"\(path)\"", forType: .string)
        }
    }

    /// Held strongly to keep the signal source alive for the process lifetime.
    private static var signalSource: DispatchSourceSignal?

    /// Registers SIGTERM handler so the app shuts down cleanly when killed.
    /// Uses DispatchSource instead of signal() — signal handlers must only call
    /// async-signal-safe functions, and DispatchQueue.main.async is NOT safe
    /// (can deadlock if the main thread holds a libdispatch lock during sleep/wake).
    public static func installSignalHandlers() {
        // Ignore the default SIGTERM action so DispatchSource can handle it
        signal(SIGTERM, SIG_IGN)

        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            NSApplication.shared.terminate(nil)
        }
        source.resume()
        signalSource = source
    }
}
