import Foundation
import os

@MainActor
final class FileWatcher {
    private var fileSource: DispatchSourceFileSystemObject?
    private var fsEventStream: FSEventStreamRef?
    private var debounceWorkItem: DispatchWorkItem?
    private var timer: Timer?
    private var retryTimer: Timer?
    private let onChange: () -> Void
    private var isStopped = false
    private var statsCacheRetryCount = 0
    private static let maxStatsCacheRetries = 10
    private static let statsCacheRetryBase: TimeInterval = 60
    private static let statsCacheRetryCap: TimeInterval = 300
    private static let debounceDelay: TimeInterval = 2.0
    private static let fallbackPollingInterval: TimeInterval = 60

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    func startWatching() {
        isStopped = false
        watchStatsCache()
        watchProjectsDirectory()
        // Start fallback timer if either watcher failed — ensures changes are
        // picked up even if one of the two FS event sources is unavailable.
        if fileSource == nil || fsEventStream == nil {
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
        guard timer == nil, fileSource == nil || fsEventStream == nil else { return }
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

        // Use a weak wrapper so FSEventStream doesn't prevent deallocation
        let weak = WeakBox(self)
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
                watcher.debounceNotify(invalidateStatsCache: false, invalidateSessionLog: true)
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
            return
        }

        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        fsEventStream = stream
    }

    /// Retry opening stats-cache with exponential backoff (60s → 120s → 240s → 300s cap, max 10 retries).
    private func scheduleStatsCacheRetry() {
        guard statsCacheRetryCount < Self.maxStatsCacheRetries else {
            AppLogger.files.info("FileWatcher: giving up on stats-cache after \(Self.maxStatsCacheRetries) retries")
            return
        }
        let delay = min(
            Self.statsCacheRetryBase * pow(2.0, Double(statsCacheRetryCount)),
            Self.statsCacheRetryCap
        )
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
    /// Stats-cache changes don't require re-scanning JSONL files, and vice versa.
    /// Fallback timer invalidates both (safe catch-all when FS events are unavailable).
    private func debounceNotify(invalidateStatsCache: Bool = true, invalidateSessionLog: Bool = true) {
        guard !isStopped else { return }
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isStopped else { return }
                if invalidateSessionLog { SessionLogReader.shared.invalidate() }
                if invalidateStatsCache { StatsCacheReader.shared.invalidate() }
                self.onChange()
            }
        }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounceDelay, execute: work)
    }

    // Nonisolated deinit cannot call @MainActor methods — inline cleanup.
    deinit {
        debounceWorkItem?.cancel()
        if let source = fileSource { source.cancel() }
        if let stream = fsEventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        timer?.invalidate()
        retryTimer?.invalidate()
    }
}

private final class WeakBox<T: AnyObject> {
    weak var value: T?
    init(_ value: T) { self.value = value }
}
