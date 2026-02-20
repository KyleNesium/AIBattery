import Foundation
import os

final class FileWatcher {
    private var fileSource: DispatchSourceFileSystemObject?
    private var fsEventStream: FSEventStreamRef?
    private var debounceWorkItem: DispatchWorkItem?
    private var timer: Timer?
    private var retryTimer: Timer?
    private let onChange: () -> Void
    private var isStopped = false

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    func startWatching() {
        isStopped = false
        watchStatsCache()
        watchProjectsDirectory()
        // Only start fallback timer if both file watchers failed —
        // avoids redundant polling when FS events are already active.
        if fileSource == nil && fsEventStream == nil {
            startFallbackTimer()
        }
    }

    func stopWatching() {
        isStopped = true
        debounceWorkItem?.cancel()
        debounceWorkItem = nil

        if let source = fileSource {
            source.cancel() // Cancel handler closes the fd
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

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.debounceNotify()
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

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let box = Unmanaged<WeakBox<FileWatcher>>.fromOpaque(info).takeUnretainedValue()
            guard let watcher = box.value else { return }
            DispatchQueue.main.async { watcher.debounceNotify() }
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

    /// Retry opening stats-cache every 60s until it exists (created after first `/stats` run).
    private func scheduleStatsCacheRetry() {
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self, !self.isStopped, self.fileSource == nil else { return }
            self.watchStatsCache()
        }
    }

    private func startFallbackTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self, !self.isStopped else { return }
            self.onChange()
        }
    }

    private func debounceNotify() {
        guard !isStopped else { return }
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isStopped else { return }
            // Invalidate reader caches so the next refresh re-scans changed files
            SessionLogReader.shared.invalidate()
            StatsCacheReader.shared.invalidate()
            self.onChange()
        }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    deinit { stopWatching() }
}

private final class WeakBox<T: AnyObject> {
    weak var value: T?
    init(_ value: T) { self.value = value }
}
