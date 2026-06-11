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
    private static let lockPath: String = AppPaths.applicationSupport()
        .appendingPathComponent("aibattery.lock").path

    /// File descriptor for the lock file — kept open for the process lifetime.
    /// Process-wide state set at startup before any concurrency is active and treated
    /// as an opaque token thereafter; `nonisolated(unsafe)` is correct — no contention.
    nonisolated(unsafe) private static var lockFD: Int32 = -1

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
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        } catch {
            AppLogger.general.warning("SingleInstanceGuard: failed to create directory: \(error.localizedDescription, privacy: .public)")
        }

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

    /// Held strongly to keep the signal source alive for the process lifetime.
    nonisolated(unsafe) private static var signalSource: DispatchSourceSignal?

    /// Registers SIGTERM handler so the app shuts down cleanly when killed.
    /// Uses DispatchSource instead of signal() — signal handlers must only call
    /// async-signal-safe functions, and DispatchQueue.main.async is NOT safe
    /// (can deadlock if the main thread holds a libdispatch lock during sleep/wake).
    public static func installSignalHandlers() {
        // Ignore the default SIGTERM action so DispatchSource can handle it
        signal(SIGTERM, SIG_IGN)

        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            // Queue is .main, so we're already on the main thread, but Swift's
            // strict concurrency can't see that from a pre-concurrency API —
            // assumeIsolated documents the invariant.
            MainActor.assumeIsolated {
                NSApplication.shared.terminate(nil)
            }
        }
        source.resume()
        signalSource = source
    }
}
