import Foundation
import os

@MainActor
final class FileWatcher {
    // These resources are written / read only from MainActor methods at runtime
    // (the @MainActor class isolation guarantees that). `nonisolated(unsafe)`
    // is required so the nonisolated `deinit` can still touch them — the deinit
    // runs on whatever thread releases the last reference, and Timer/
    // FSEventStreamRef/DispatchWorkItem cleanup APIs are documented thread-safe.
    nonisolated(unsafe) private var fileSource: DispatchSourceFileSystemObject?
    nonisolated(unsafe) private var fsEventStream: FSEventStreamRef?
    /// Second FSEvents root: `~/.codex/sessions` (Codex CLI rollouts). Absent when the
    /// directory doesn't exist — that is not a failure and starts no fallback timer.
    nonisolated(unsafe) private var codexFsEventStream: FSEventStreamRef?
    /// True only when `~/.codex/sessions` exists but its stream could not be created.
    private var codexWatchFailed = false
    nonisolated(unsafe) private var debounceWorkItem: DispatchWorkItem?
    nonisolated(unsafe) private var timer: Timer?
    nonisolated(unsafe) private var retryTimer: Timer?
    private let onChange: () -> Void
    private var isStopped = false
    private var statsCacheRetryCount = 0
    private static let debounceDelay: TimeInterval = 2.0
    private static let fallbackPollingInterval: TimeInterval = 60

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    func startWatching() {
        isStopped = false
        watchStatsCache()
        watchProjectsDirectory()
        watchCodexSessionsDirectory()
        // Start fallback timer if any attempted watcher failed — ensures changes are
        // picked up even if one of the FS event sources is unavailable.
        if fileSource == nil || fsEventStream == nil || codexWatchFailed {
            startFallbackTimer()
        }
    }

    /// Pause the fallback timer without tearing down FSEvent watchers.
    /// Called when the system goes idle or locks — FS events continue, polling stops.
    func suspendFallbackTimer() {
        timer?.invalidate()
        timer = nil
    }

    /// Resume the fallback timer if FSEvent watchers are absent.
    func resumeFallbackTimer() {
        guard timer == nil, fileSource == nil || fsEventStream == nil || codexWatchFailed else { return }
        startFallbackTimer()
    }

    func stopWatching() {
        isStopped = true
        debounceWorkItem?.cancel()
        debounceWorkItem = nil

        if let source = fileSource {
            source.cancel()
            fileSource = nil
        }

        if let stream = fsEventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            fsEventStream = nil
        }

        if let stream = codexFsEventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            codexFsEventStream = nil
        }
        codexWatchFailed = false

        timer?.invalidate()
        timer = nil

        retryTimer?.invalidate()
        retryTimer = nil
        statsCacheRetryCount = 0
    }

    private func watchStatsCache() {
        let path = ClaudePaths.statsCachePath
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            AppLogger.files.warning("FileWatcher: stats-cache not found, will retry in 60s")
            scheduleStatsCacheRetry()
            return
        }
        retryTimer?.invalidate()
        retryTimer = nil
        statsCacheRetryCount = 0

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.debounceNotify(invalidateStatsCache: true, invalidateSessionLog: false)
            }
        }

        // Close fd when source is cancelled — single owner
        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        fileSource = source
    }

    private func watchProjectsDirectory() {
        let path = ClaudePaths.projectsPath
        guard FileManager.default.fileExists(atPath: path) else {
            AppLogger.files.warning("FileWatcher: projects directory not found at \(path, privacy: .public), falling back to timer only")
            return
        }
        fsEventStream = makeDirectoryStream(path: path) { watcher in
            watcher.debounceNotify(invalidateStatsCache: false, invalidateSessionLog: true, invalidateCodexSessionLog: false)
        }
    }

    /// Watch `~/.codex/sessions` for Codex CLI rollout writes. Missing directory →
    /// silently skipped (no Codex CLI on this machine); creation failure → fallback timer.
    private func watchCodexSessionsDirectory() {
        let path = CodexPaths.sessionsPath
        guard FileManager.default.fileExists(atPath: path) else { return }
        codexFsEventStream = makeDirectoryStream(path: path) { watcher in
            watcher.debounceNotify(invalidateStatsCache: false, invalidateSessionLog: false, invalidateCodexSessionLog: true)
        }
        codexWatchFailed = codexFsEventStream == nil
    }

    /// Create + start a file-level FSEventStream on `path` whose callback runs on main.
    /// `onEvent` receives the still-alive watcher. Returns nil (and logs) on failure.
    private func makeDirectoryStream(path: String, onEvent: @escaping @MainActor (FileWatcher) -> Void) -> FSEventStreamRef? {
        // Use a weak wrapper so FSEventStream doesn't prevent deallocation
        let weak = WeakBox(self, onEvent: onEvent)
        let ptr = Unmanaged.passRetained(weak).toOpaque()

        var context = FSEventStreamContext()
        context.info = ptr
        context.release = { p in
            guard let p else { return }
            Unmanaged<WeakBox<FileWatcher>>.fromOpaque(p).release()
        }

        // Callback runs on .main (set via FSEventStreamSetDispatchQueue below)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let box = Unmanaged<WeakBox<FileWatcher>>.fromOpaque(info).takeUnretainedValue()
            guard let watcher = box.value else { return }
            MainActor.assumeIsolated {
                box.onEvent?(watcher)
            }
        }

        guard let stream = FSEventStreamCreate(
            nil, callback, &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            2.0,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        ) else {
            AppLogger.files.warning("FileWatcher: failed to create FSEventStream for \(path, privacy: .public)")
            return nil
        }

        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        return stream
    }

    /// Retry opening stats-cache with exponential backoff via `RetryPolicy.fileWatch`
    /// (60s → 120s → 240s → 300s cap, no jitter, max 10 retries).
    private func scheduleStatsCacheRetry() {
        let policy = RetryPolicy.fileWatch
        guard let maxAttempts = policy.maxAttempts, statsCacheRetryCount < maxAttempts else {
            AppLogger.files.info("FileWatcher: giving up on stats-cache after \(policy.maxAttempts ?? 0) retries")
            return
        }
        // Historical convention: retryCount is 0-indexed (first retry → count=0).
        // RetryPolicy is 1-indexed, so count+1 maps directly.
        let delay = policy.delay(forAttempt: statsCacheRetryCount + 1)
        statsCacheRetryCount += 1
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isStopped, self.fileSource == nil else { return }
                self.watchStatsCache()
            }
        }
    }

    private func startFallbackTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: Self.fallbackPollingInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isStopped else { return }
                self.onChange()
            }
        }
    }

    /// Selective invalidation — only clear the cache for the reader whose data actually changed.
    /// Stats-cache changes don't require re-scanning JSONL files, and vice versa; a Codex
    /// rollout write touches neither Claude reader.
    private func debounceNotify(invalidateStatsCache: Bool = true, invalidateSessionLog: Bool = true, invalidateCodexSessionLog: Bool = false) {
        guard !isStopped else { return }
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isStopped else { return }
                if invalidateSessionLog {
                    SessionLogReader.shared.invalidate()
                }
                if invalidateStatsCache {
                    StatsCacheReader.shared.invalidate()
                }
                if invalidateCodexSessionLog {
                    CodexSessionLogReader.shared.invalidate()
                }
                self.onChange()
            }
        }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounceDelay, execute: work)
    }

    deinit {
        debounceWorkItem?.cancel()
        if let source = fileSource {
            source.cancel()
        }
        for stream in [fsEventStream, codexFsEventStream].compactMap({ $0 }) {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        timer?.invalidate()
        retryTimer?.invalidate()
    }
}

/// Weak reference + per-stream event handler handed to the FSEvents C callback.
private final class WeakBox<T: AnyObject> {
    weak var value: T?
    let onEvent: (@MainActor (T) -> Void)?
    init(_ value: T, onEvent: (@MainActor (T) -> Void)? = nil) {
        self.value = value
        self.onEvent = onEvent
    }
}
