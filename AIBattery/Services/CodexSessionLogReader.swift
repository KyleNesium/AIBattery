import Foundation
import os

/// Reads and caches Codex CLI rollout JSONL under `~/.codex/sessions/YYYY/MM/DD/`.
/// Sibling of `SessionLogReader` with the same discipline: NOT MainActor, FileHandle
/// streaming (never a whole file in memory), fingerprint-only per-file cache with raw
/// arrays released after merge, incremental rebuild of changed files only, non-blocking
/// `invalidate()`. Line parsing is delegated to `CodexSessionLogParser` (token counts
/// only — `response_item` content is never decoded).
final class CodexSessionLogReader: @unchecked Sendable, UsageEntrySource {
    private let lock = NSLock()
    /// Set by invalidate() when a scan holds the lock — checked after the scan completes.
    private let pendingInvalidation = NSLock.AtomicBool()
    static let shared = CodexSessionLogReader()

    private let sessionsURL: URL

    init(sessionsURL: URL? = nil) {
        self.sessionsURL = sessionsURL ?? CodexPaths.sessions
    }

    // MARK: - Cache types

    /// Per-file cache entry: fingerprint (modDate + fileSize) + the message IDs this
    /// file contributed (for stale-entry removal). `entries` is nil after eviction for
    /// files not modified today — the merged `cachedAllEntries` is authoritative then.
    struct FileCacheEntry {
        let modDate: Date
        let fileSize: UInt64
        var entries: [AssistantUsageEntry]?
        var messageIds: Set<String>
    }

    private var cache: [String: FileCacheEntry] = [:]
    /// Starts true so the first read performs a full scan.
    private var isDirty = true
    private var cachedAllEntries: [AssistantUsageEntry]?

    /// The message ids of `cachedAllEntries`, written together with it. Rebuilding this
    /// from the merged array cost a string hash per entry on every dirty cycle.
    private var cachedSeenIds: Set<String>?

    /// Maximum time between directory enumerations, as a safety net behind the
    /// per-directory mtime cache below.
    static let discoveryTTL: TimeInterval = 60
    private var discoveredFiles: [URL]?
    private var lastEnumerationDate: Date?
    private var rootModDateAtEnumeration: Date?

    /// One directory's contents plus the mtime they were read at.
    ///
    /// A directory's mtime moves whenever an entry is added or removed, so an unchanged
    /// mtime means BOTH lists are still accurate and the directory needs no read at all.
    private struct DirListing {
        var modDate: Date?
        var files: [URL]
        var subdirectories: [URL]
    }

    /// Per-directory listings, keyed by path and deliberately kept across `invalidate()`
    /// — that is the whole point. Discovery used to re-walk the entire tree and resolve
    /// every file's symlink on each invalidation (roughly 15–40 ms per cycle, every two
    /// seconds during an active session) because the only short-circuit was the root's
    /// mtime, which changes about once a year.
    private var dirListings: [String: DirListing] = [:]

    /// How many directories the last discovery actually read, as opposed to served from
    /// `dirListings`. Tests assert this drops once the tree is warm.
    private var directoriesListedDuringLastDiscovery = 0

    /// Corrupt / skipped line count from the most recent `readAllUsageEntries()`.
    /// Written on the scan thread, read from MainActor — see `NSLock.AtomicInt`.
    private let corruptLineCounter = NSLock.AtomicInt()
    var lastCorruptLineCount: Int { corruptLineCounter.current }

    // MARK: - UsageEntrySource

    /// Non-blocking: if a scan holds the lock, flags it so that scan's result is
    /// discarded and the next read re-scans. Never clears the per-file fingerprints or
    /// the merged result — both are reused for the incremental rebuild.
    func invalidate() {
        if lock.try() {
            isDirty = true
            discoveredFiles = nil
            lastEnumerationDate = nil
            lock.unlock()
        } else {
            pendingInvalidation.set(true)
        }
    }

    func readAllUsageEntries() -> [AssistantUsageEntry] {
        lock.lock()
        pendingInvalidation.set(false)
        corruptLineCounter.set(0)

        if !isDirty, let cached = cachedAllEntries {
            lock.unlock()
            return cached
        }

        isDirty = false
        let files = discoverJSONLFiles()

        // Purge deleted files: drop their cache entry and their entries from the merge.
        let currentPaths = Set(files.map(\.path))
        let staleKeys = cache.keys.filter { !currentPaths.contains($0) }
        if !staleKeys.isEmpty {
            var idsToRemove = Set<String>()
            for key in staleKeys {
                idsToRemove.formUnion(cache[key]?.messageIds ?? [])
                cache.removeValue(forKey: key)
            }
            if !idsToRemove.isEmpty, let existing = cachedAllEntries {
                cachedAllEntries = existing.filter { !idsToRemove.contains($0.messageId) }
                cachedSeenIds?.subtract(idsToRemove)
            }
        }

        let (result, resultIds) = rebuild(files: files, base: cachedAllEntries, baseIds: cachedSeenIds)

        if pendingInvalidation.swap(false) {
            isDirty = true
            lock.unlock()
            return result
        }

        cachedAllEntries = result
        cachedSeenIds = resultIds
        evictOldFileEntries()
        lock.unlock()
        return result
    }

    // MARK: - Rebuild / eviction

    private func rebuild(
        files: [URL],
        base: [AssistantUsageEntry]?,
        baseIds: Set<String>?
    ) -> ([AssistantUsageEntry], Set<String>) {
        var resultEntries = base ?? []
        // Reuse the previous cycle's id set rather than rehashing every message id.
        var seenIds = baseIds ?? Set(resultEntries.map(\.messageId))
        var changed = false

        for fileURL in files {
            let path = fileURL.path
            // See SessionLogReader: `resourceValues` avoids bridging a full attribute
            // dictionary per file (~9x faster over a tree this size).
            // NSURL caches resource values on the URL, so a reused instance would keep
            // reporting the pre-write modDate/size and the file would never be re-parsed.
            var fileURL = fileURL
            fileURL.removeAllCachedResourceValues()
            let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let modDate = values?.contentModificationDate
            let fileSize = values?.fileSize.map(UInt64.init)

            if let cached = cache[path], cached.modDate == modDate, cached.fileSize == fileSize {
                // Unchanged. Live entries (today's file) may not be in a nil base yet.
                if let live = cached.entries {
                    for entry in live where seenIds.insert(entry.messageId).inserted {
                        resultEntries.append(entry)
                        changed = true
                    }
                }
                continue
            }

            // New or changed: drop this file's previous contribution, then re-parse.
            if let cached = cache[path], !cached.messageIds.isEmpty {
                let staleIds = cached.messageIds
                resultEntries.removeAll { staleIds.contains($0.messageId) }
                seenIds.subtract(staleIds)
                changed = true
            }

            let entries = readSessionFile(at: fileURL)
            cache[path] = FileCacheEntry(
                modDate: modDate ?? Date(),
                fileSize: fileSize ?? 0,
                entries: entries,
                messageIds: Set(entries.map(\.messageId))
            )
            for entry in entries where seenIds.insert(entry.messageId).inserted {
                resultEntries.append(entry)
                changed = true
            }
        }

        if changed || base == nil {
            resultEntries.sort { $0.timestamp < $1.timestamp }
        }
        return (resultEntries, seenIds)
    }

    /// Release raw entry arrays for files not modified today — fingerprints and
    /// message IDs stay so a later change can still purge the file's stale entries.
    private func evictOldFileEntries() {
        let today = Calendar.current.startOfDay(for: Date())
        // Collect first: mutating `cache` while iterating it copies the whole dictionary.
        let stalePaths = cache.compactMap { path, entry -> String? in
            entry.entries != nil && entry.modDate < today ? path : nil
        }
        for path in stalePaths {
            cache[path]?.entries = nil
        }
    }

    /// Number of per-file cache entries still holding live entry arrays (tests).
    func cacheEntriesWithLiveEntriesCountForTesting() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return cache.values.filter { $0.entries != nil }.count
    }

    // MARK: - Discovery

    private func discoverJSONLFiles() -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sessionsURL.path) else { return [] }

        let rootModDate = FileStat.modificationDate(of: sessionsURL)
        if let cached = discoveredFiles,
           let lastEnum = lastEnumerationDate,
           Date().timeIntervalSince(lastEnum) < Self.discoveryTTL,
           rootModDate == rootModDateAtEnumeration {
            return cached
        }

        let resolvedBase = sessionsURL.resolvingSymlinksInPath().path
        let resolvedBaseSlash = resolvedBase + "/"
        var files: [URL] = []
        var liveDirPaths = Set<String>()
        var listedCount = 0

        // Breadth-first over the YYYY/MM/DD skeleton. An unchanged directory costs one
        // stat and nothing else; only directories whose mtime moved are read.
        var queue = [sessionsURL]
        while let dir = queue.popLast() {
            let path = dir.path
            guard liveDirPaths.insert(path).inserted else { continue } // cycle guard

            let modDate = FileStat.modificationDate(of: dir)
            let listing: DirListing
            if let cached = dirListings[path], let modDate, cached.modDate == modDate {
                listing = cached
            } else {
                listing = listDirectory(
                    dir, fileManager: fm,
                    resolvedBase: resolvedBase, resolvedBaseSlash: resolvedBaseSlash,
                    modDate: modDate
                )
                dirListings[path] = listing
                listedCount += 1
            }

            files.append(contentsOf: listing.files)
            queue.append(contentsOf: listing.subdirectories.filter {
                Self.isWithinRetentionHorizon(directory: $0, under: sessionsURL, now: Date())
            })
        }

        // Forget directories that no longer exist, so a deleted date folder cannot keep
        // feeding its files into discovery.
        if dirListings.count != liveDirPaths.count {
            dirListings = dirListings.filter { liveDirPaths.contains($0.key) }
        }

        directoriesListedDuringLastDiscovery = listedCount
        discoveredFiles = files
        lastEnumerationDate = Date()
        rootModDateAtEnumeration = rootModDate
        return files
    }

    /// Months of history worth discovering. The aggregator never looks past 12 months
    /// and Codex all-time figures are a `TokenLedger` high-water mark (so they survive a
    /// file disappearing), but the Codex CLI never prunes its rollouts, so the tree grows
    /// without bound — measured 2026-10-31: 1734 files, 105 of them already past 90 days.
    /// 13 rather than 12 so the boundary month is always read whole.
    ///
    /// `SessionLogReader` deliberately has no equivalent: Claude Code prunes its own
    /// session logs at ~45 days (same machine, same day: 2700 files, oldest 46 days), so a
    /// horizon there would skip nothing and only cost a date prefetch per discovery pass.
    /// See `docs/TODOS.md` → "Decided not to do".
    static let retentionHorizonMonths = 13

    /// Whether a `~/.codex/sessions/YYYY[/MM[/DD]]` directory can still hold anything
    /// worth reading. The date is in the path, so this costs no `stat`.
    ///
    /// Anything that does not parse as part of that skeleton is kept: an unrecognised
    /// layout must not silently drop a user's data.
    static func isWithinRetentionHorizon(directory: URL, under root: URL, now: Date) -> Bool {
        let rootComponents = root.standardizedFileURL.pathComponents
        let components = directory.standardizedFileURL.pathComponents
        guard components.count > rootComponents.count,
              Array(components.prefix(rootComponents.count)) == rootComponents else { return true }
        let relative = Array(components.dropFirst(rootComponents.count))

        guard let year = Int(relative[0]), (1_970...9_999).contains(year) else { return true }
        var month = 12 // a bare year folder is kept if ANY of its months is in range
        if relative.count >= 2 {
            guard let parsed = Int(relative[1]), (1...12).contains(parsed) else { return true }
            month = parsed
        }

        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .month, value: -retentionHorizonMonths, to: now) else { return true }
        let cutoffYear = calendar.component(.year, from: cutoff)
        let cutoffMonth = calendar.component(.month, from: cutoff)
        return (year, month) >= (cutoffYear, cutoffMonth)
    }

    /// Read one directory: its `.jsonl` files and its subdirectories.
    ///
    /// The symlink boundary is enforced per entry rather than by resolving every file.
    /// Only entries that ARE symlinks are resolved, which is what made the old version
    /// expensive — `resolvingSymlinksInPath()` is a multi-component `realpath` and it
    /// ran on all 900-odd files whether or not any of them was a link.
    private func listDirectory(
        _ dir: URL,
        fileManager fm: FileManager,
        resolvedBase: String,
        resolvedBaseSlash: String,
        modDate: Date?
    ) -> DirListing {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        guard let entries = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else {
            return DirListing(modDate: modDate, files: [], subdirectories: [])
        }

        var files: [URL] = []
        var subdirectories: [URL] = []

        for entry in entries {
            guard let values = try? entry.resourceValues(forKeys: Set(keys)) else { continue }

            let isLink = values.isSymbolicLink == true
            if isLink {
                let resolved = entry.resolvingSymlinksInPath().path
                guard resolved == resolvedBase || resolved.hasPrefix(resolvedBaseSlash) else { continue }
            }

            if values.isDirectory == true {
                // Descend into real directories only. A symlinked directory inside the
                // sessions tree is not something Codex creates, and refusing to follow
                // one removes any chance of a traversal cycle.
                if !isLink {
                    subdirectories.append(entry)
                }
            } else if entry.pathExtension == "jsonl", values.isRegularFile == true {
                files.append(entry)
            }
        }

        return DirListing(modDate: modDate, files: files, subdirectories: subdirectories)
    }

    /// Directories read (not served from cache) by the most recent discovery — tests only.
    func directoriesListedDuringLastDiscoveryForTesting() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return directoriesListedDuringLastDiscovery
    }

    // MARK: - Streaming line reader

    private func readSessionFile(at url: URL) -> [AssistantUsageEntry] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        var parser = CodexSessionLogParser(fallbackSessionId: url.deletingPathExtension().lastPathComponent)
        var entries: [AssistantUsageEntry] = []
        var lineIndex = 0

        let bufferSize = 64 * 1_024
        let maxLineSize = 1_048_576 // 1 MB — discard oversized (malformed) lines
        var leftover = Data()
        /// Set once a line passes `maxLineSize` without a newline; bytes are dropped
        /// until that newline so the line is counted once and its tail never parsed.
        var skippingOversizedLine = false

        func process(_ lineData: Data) {
            defer { lineIndex += 1 }
            guard !lineData.isEmpty, CodexSessionLogParser.mightBeRelevant(lineData) else { return }
            if let entry = parser.consume(line: lineData, lineIndex: lineIndex) {
                entries.append(entry)
            }
        }

        // One reused buffer for the whole file: a `Data` per chunk was the launch
        // footprint spike (see `ChunkedFileReader`).
        var chunkReader = ChunkedFileReader(handle: handle, bufferSize: bufferSize)

        while true {
            // Bytes already searched for a newline on a previous pass — a multi-megabyte
            // line arrives in many chunks and must not be rescanned from its start each time.
            var alreadyScanned = leftover.count
            guard chunkReader.readChunk(into: &leftover) else { break }

            if skippingOversizedLine {
                guard let newlineIndex = leftover.firstNewlineIndex(from: leftover.startIndex + alreadyScanned) else {
                    leftover.removeAll()
                    continue
                }
                leftover = Data(leftover[(newlineIndex + 1)...])
                alreadyScanned = 0
                skippingOversizedLine = false
            } else if leftover.count > maxLineSize, leftover.firstNewlineIndex(from: leftover.startIndex + alreadyScanned) == nil {
                corruptLineCounter.add(1)
                AppLogger.files.debug("Skipping oversized Codex JSONL line (>\(leftover.count) bytes) in \(url.lastPathComponent, privacy: .public)")
                leftover.removeAll()
                skippingOversizedLine = true
                continue
            }

            var searchFrom = leftover.startIndex + alreadyScanned
            while let newlineIndex = leftover.firstNewlineIndex(from: searchFrom) {
                // A slice, not a copy: most lines are multi-KB (or multi-MB) `response_item`
                // records that the 512-byte pre-filter rejects — copying each one first
                // cost ~80–160 ms per cold scan and 2–10 ms per invalidation.
                let lineData = leftover[leftover.startIndex..<newlineIndex]
                leftover = leftover[(newlineIndex + 1)...]
                searchFrom = leftover.startIndex
                process(lineData)
            }

            // Compact so slice chains don't pin the whole read buffer.
            if leftover.startIndex != 0 {
                leftover = Data(leftover)
            }
        }

        // Trailing data without a newline: only a complete object (ends with `}`) is a
        // finished line — anything else is a partial write still in progress.
        if !skippingOversizedLine, !leftover.isEmpty, leftover.last == UInt8(ascii: "}") {
            process(leftover)
        }

        corruptLineCounter.add(parser.corruptLineCount)
        return entries
    }
}
