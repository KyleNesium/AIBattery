import Foundation
import os

// MARK: - AtomicBool

extension NSLock {
    /// Lock-protected boolean for cross-thread flag signaling.
    final class AtomicBool: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false

        func set(_ newValue: Bool) {
            lock.lock()
            value = newValue
            lock.unlock()
        }

        /// Atomically reads the current value, sets it to `newValue`, and returns the old value.
        func swap(_ newValue: Bool) -> Bool {
            lock.lock()
            let old = value
            value = newValue
            lock.unlock()
            return old
        }
    }

    /// Lock-protected counter for a value written on a scan thread and read from
    /// MainActor. Its own lock, deliberately: the reader's scan lock is held for the
    /// whole of a cold scan, so reading through it would park the UI thread behind
    /// seconds of file I/O — the thing these readers exist to avoid.
    final class AtomicInt: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        var current: Int {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func set(_ newValue: Int) {
            lock.lock()
            value = newValue
            lock.unlock()
        }

        func add(_ delta: Int) {
            lock.lock()
            value += delta
            lock.unlock()
        }
    }
}

/// Reads and caches JSONL session log files. NOT MainActor — file I/O must not block the UI.
/// Thread-safety: mutable state accessed behind `lock`. `invalidate()` uses `tryLock` so
/// FileWatcher on main never blocks waiting for a long-running background scan.
final class SessionLogReader: @unchecked Sendable {
    private let lock = NSLock()
    /// Set true by invalidate() when lock is held by a scan — checked after scan completes.
    /// Atomic: written by FileWatcher (main) without the lock, read by background scan under the lock.
    private let pendingInvalidation = NSLock.AtomicBool()
    static let shared = SessionLogReader()

    private let projectsURL: URL

    init(projectsURL: URL? = nil) {
        self.projectsURL = projectsURL ?? ClaudePaths.projects
    }

    // MARK: - Cache types

    /// Per-file cache entry. After a successful merge into cachedAllEntries, `entries` is
    /// set to nil for files not modified today — releasing raw entry arrays while retaining
    /// the fingerprint (modDate + fileSize) and messageIds (for stale-entry removal).
    struct FileCacheEntry {
        let modDate: Date
        let fileSize: UInt64
        /// Raw entries — nil after eviction for old files. Re-populated on re-parse if file changes.
        var entries: [AssistantUsageEntry]?
        /// Message IDs contributed by this file — retained after eviction so stale entries
        /// can be removed from cachedAllEntries when the file is re-parsed.
        var messageIds: Set<String>
        /// Byte offset the next parse of this file can resume from, and what the previous
        /// parse's unterminated trailing line contributed. Both are only usable while
        /// `entries` is live; an evicted file re-parses in full.
        var resumeOffset: UInt64 = 0
        var trailing: FileParse.TrailingContribution?
        /// First bytes of the file as last parsed. A changed head means the file was
        /// rewritten or rotated rather than appended to, so the offset is meaningless.
        var headFingerprint: Data = .init()
    }

    /// Bytes compared to decide "same file, just longer". Enough to cover the first
    /// JSONL line's session metadata; a rewrite changes it immediately.
    static let headFingerprintLength = 256

    // Cache: filePath -> FileCacheEntry (entries may be nil after eviction)
    private var cache: [String: FileCacheEntry] = [:]

    /// Dirty flag — set by invalidate(), cleared by readAllUsageEntries().
    /// Starts true so the first read performs a full scan.
    private var isDirty = true

    /// Maximum time between full directory enumerations, regardless of mod-date changes.
    /// Catches new files on filesystems where directory mtime doesn't always update.
    static let discoveryTTL: TimeInterval = 60

    /// Cached result of readAllUsageEntries — the authoritative merged array.
    /// Preserved across invalidations so incremental rebuilds can add only changed files.
    private var cachedAllEntries: [AssistantUsageEntry]?

    /// The message ids of `cachedAllEntries`, kept in step with it. Rebuilding this from
    /// the merged array cost a string hash per entry on every dirty cycle — tens of
    /// thousands of them — to re-learn something the previous cycle already knew.
    /// Always written together with `cachedAllEntries`; `nil` means "not yet computed".
    private var cachedSeenIds: Set<String>?

    /// Cached list of discovered JSONL file URLs.
    private var discoveredFiles: [URL]?
    /// Parent directory mod dates used to invalidate discovery cache.
    private var discoveryDirModDates: [String: Date] = [:]
    /// Per-directory cached JSONL file URLs — keyed by project directory path.
    /// Preserved across invalidation cycles so unchanged directories skip enumeration.
    private var discoveredFilesByDir: [String: [URL]] = [:]
    /// Timestamp of the last full directory enumeration. Used as TTL fallback
    /// when directory mod-dates don't reflect new files (filesystem-dependent).
    private var lastFullEnumerationDate: Date?

    /// Pre-computed byte markers for fast JSONL pre-filtering (avoids re-allocating per file).
    private static let assistantMarkers: [Data] = [
        "\"type\":\"assistant\"",
        "\"type\": \"assistant\"",
    ].compactMap { $0.data(using: .utf8) }
    private static let usageMarker: Data = "\"usage\"".data(using: .utf8) ?? Data()
    /// Shared decoder — avoids allocating a new one per JSONL file.
    private static let jsonDecoder = JSONDecoder()

    /// Number of corrupt/skipped lines from the most recent file parse cycle. Written
    /// on the scan thread, read from MainActor (`UsageViewModel.logCorruptionMetrics`) —
    /// so it is an atomic rather than a plain `Int` guarded by nothing.
    private let corruptLineCounter = NSLock.AtomicInt()
    var lastCorruptLineCount: Int { corruptLineCounter.current }

    /// Called by FileWatcher when files change — marks caches dirty so the next read re-scans.
    /// Non-blocking: if a scan is in progress, sets a flag so the scan result is discarded.
    /// Does NOT clear per-file cache — unchanged files keep their cached fingerprints.
    /// Does NOT clear cachedAllEntries — preserved for incremental rebuilds.
    func invalidate() {
        if lock.try() {
            isDirty = true
            discoveredFiles = nil
            // Keep discoveryDirModDates and discoveredFilesByDir for incremental comparison —
            // next discovery will only enumerate directories whose mod-date changed.
            //
            // `lastFullEnumerationDate` is deliberately NOT cleared. Clearing it made
            // `discoverJSONLFiles` compute `forceFullEnum == true`, which gates OFF the
            // per-directory mod-date skip — the exact opposite of what the old comment
            // here claimed. Nilling `discoveredFiles` above is already enough to force a
            // re-discovery that takes the cheap per-dir path. Measured on a 1722-file
            // tree: full enumeration 19.4 ms vs 1.0 ms for the incremental path, paid on
            // every invalidation rather than once per TTL.
            lock.unlock()
        } else {
            // Scan in progress — mark for invalidation when it finishes.
            // Atomic so FileWatcher on main never blocks waiting for the scan lock.
            pendingInvalidation.set(true)
        }
    }

    func readAllUsageEntries() -> [AssistantUsageEntry] {
        lock.lock()
        pendingInvalidation.set(false)
        corruptLineCounter.set(0)

        // Fast path: not dirty, return cached result
        if !isDirty, let cached = cachedAllEntries {
            lock.unlock()
            return cached
        }

        isDirty = false
        let jsonlFiles = discoverJSONLFiles()

        // Remove cache entries for deleted files and purge their entries from cachedAllEntries.
        let currentPaths = Set(jsonlFiles.map(\.path))
        let staleKeys = cache.keys.filter { !currentPaths.contains($0) }
        if !staleKeys.isEmpty {
            // Compute the set of messageIds to remove from cachedAllEntries.
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

        // Incremental rebuild: use cachedAllEntries as base, only re-parse changed/new files.
        // For evicted files with unchanged fingerprint, entries already live in cachedAllEntries.
        let (result, resultIds) = rebuild(
            jsonlFiles: jsonlFiles, base: cachedAllEntries, baseIds: cachedSeenIds
        )

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

    /// Rebuild the merged entry array, using `base` as a starting point.
    /// For each file:
    ///   - Unchanged + evicted (entries == nil): already in base — skip.
    ///   - Unchanged + live entries: add any not yet in base (handles first-run where base was nil).
    ///   - Changed or new: remove stale messageIds from base, re-parse, add fresh entries.
    ///   - base == nil: parse all files from scratch.
    private func rebuild(
        jsonlFiles: [URL],
        base: [AssistantUsageEntry]?,
        baseIds: Set<String>?
    ) -> ([AssistantUsageEntry], Set<String>) {
        var resultEntries = base ?? []
        // Reuse the previous cycle's id set when it is in step with `base`; only the
        // first pass (or a reader that was invalidated) pays the full rehash.
        var seenIds = baseIds ?? Set(resultEntries.map(\.messageId))
        var changed = false

        for fileURL in jsonlFiles {
            let path = fileURL.path

            // `FileManager.attributesOfItem` bridges a full ~15-key NSDictionary per file
            // just for these two values — measured at 71.7 ms across 1722 files versus
            // 7.8 ms for `resourceValues`, paid on every invalidation cycle while a
            // session is actively writing.
            // NSURL caches resource values on the URL instance, so a reused one keeps
            // reporting the pre-write modDate/size — the fingerprint would match, the
            // file would never be re-parsed, and edits would silently never appear.
            var fileURL = fileURL
            fileURL.removeAllCachedResourceValues()
            let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let modDate = values?.contentModificationDate
            let fileSize = values?.fileSize.map(UInt64.init)

            if let cached = cache[path],
               cached.modDate == modDate,
               cached.fileSize == fileSize {
                // Unchanged fingerprint.
                if let liveEntries = cached.entries {
                    // Entries still in memory (today's file not yet evicted).
                    // Add any that aren't already in the base (handles nil-base first-run).
                    for entry in liveEntries {
                        if seenIds.insert(entry.messageId).inserted {
                            resultEntries.append(entry)
                            changed = true
                        }
                    }
                }
                // entries == nil (evicted, unchanged): already in base — skip.
                continue
            }

            // File is new or changed. Remove any stale entries from this file before adding fresh.
            if let cached = cache[path], !cached.messageIds.isEmpty {
                let staleIds = cached.messageIds
                resultEntries.removeAll { staleIds.contains($0.messageId) }
                seenIds.subtract(staleIds)
                changed = true
            }

            // Re-parse — from the top, or from where the last parse stopped when the
            // file has simply grown (the active session file is 7-10 MB and is rewritten
            // from byte 0 on every debounced write otherwise).
            let head = Self.headBytes(of: fileURL)
            let resumeFrom = Self.tailParseOffset(cached: cache[path], newSize: fileSize, head: head)
            let parse = readSessionFile(at: fileURL, from: resumeFrom ?? 0)
            let merged: [AssistantUsageEntry] = if let resumeFrom, let previous = cache[path]?.entries {
                Self.mergingTail(
                    parse.entries, into: previous, undoing: cache[path]?.trailing
                )
            } else {
                parse.entries
            }
            let newIds = Set(merged.map(\.messageId))
            cache[path] = FileCacheEntry(
                modDate: modDate ?? Date(),
                fileSize: fileSize ?? 0,
                entries: merged,
                messageIds: newIds,
                resumeOffset: parse.resumeOffset,
                trailing: parse.trailing,
                headFingerprint: head
            )
            // A tail parse coalesces into entries that are already in the result, so the
            // result's copies have to be refreshed rather than skipped as "already seen".
            // Tool calls are the only field a continuation line changes.
            if resumeFrom != nil {
                let toolCallsById = Dictionary(
                    merged.map { ($0.messageId, $0.toolCallCount) }, uniquingKeysWith: { _, last in last }
                )
                for index in resultEntries.indices {
                    guard let fresh = toolCallsById[resultEntries[index].messageId],
                          fresh != resultEntries[index].toolCallCount else { continue }
                    resultEntries[index] = Self.addingToolCalls(
                        fresh - resultEntries[index].toolCallCount, to: resultEntries[index]
                    )
                    changed = true
                }
            }
            for entry in merged {
                if seenIds.insert(entry.messageId).inserted {
                    resultEntries.append(entry)
                    changed = true
                }
            }
        }

        if changed || base == nil {
            resultEntries.sort { $0.timestamp < $1.timestamp }
        }
        return (resultEntries, seenIds)
    }

    // MARK: - Incremental tail parse

    /// First `headFingerprintLength` bytes of a file, or empty when unreadable.
    static func headBytes(of url: URL) -> Data {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return Data() }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: headFingerprintLength)) ?? Data()
    }

    /// Where a re-parse of this file may resume, or nil when it must start from the top.
    ///
    /// Only an append qualifies: same head bytes, a size at least as large as what was
    /// already consumed, and the previous parse's entries still in memory (an evicted
    /// file has nothing to merge the tail into). A truncation, a rotation, or an edit
    /// anywhere before the offset all change one of those and fall back to a full parse.
    static func tailParseOffset(cached: FileCacheEntry?, newSize: UInt64?, head: Data) -> UInt64? {
        guard let cached, cached.entries != nil, cached.resumeOffset > 0, !cached.headFingerprint.isEmpty, cached.headFingerprint == head, let newSize, newSize >= cached.resumeOffset else { return nil }
        return cached.resumeOffset
    }

    /// Merge a tail parse into the entries a previous parse of the same file produced.
    ///
    /// - The previous pass's unterminated trailing line is undone first: the tail re-reads
    ///   that line, so without this its tool calls would be counted twice (or its entry
    ///   duplicated).
    /// - A tail entry whose message id is already known is a continuation of that message
    ///   (Claude Code writes one line per content block, all sharing `message.id` and
    ///   carrying identical usage), so only its tool calls are added — never its tokens.
    static func mergingTail(
        _ tail: [AssistantUsageEntry],
        into previous: [AssistantUsageEntry],
        undoing trailing: FileParse.TrailingContribution?
    ) -> [AssistantUsageEntry] {
        var merged = previous
        if let trailing {
            if trailing.createdEntry {
                merged.removeAll { $0.messageId == trailing.messageId }
            } else if trailing.toolCalls > 0,
                      let index = merged.firstIndex(where: { $0.messageId == trailing.messageId }) {
                merged[index] = addingToolCalls(-trailing.toolCalls, to: merged[index])
            }
        }

        var indexById = Dictionary(
            merged.enumerated().map { ($0.element.messageId, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        for entry in tail {
            if let index = indexById[entry.messageId] {
                if entry.toolCallCount > 0 {
                    merged[index] = addingToolCalls(entry.toolCallCount, to: merged[index])
                }
            } else {
                indexById[entry.messageId] = merged.count
                merged.append(entry)
            }
        }
        return merged
    }

    /// Release raw entry arrays from per-file cache for files not modified today.
    /// Only the fingerprint (modDate + fileSize) and messageIds are retained.
    /// cachedAllEntries remains the authoritative source for these entries.
    private func evictOldFileEntries() {
        let today = Calendar.current.startOfDay(for: Date())
        // Collect first: mutating `cache` while iterating it forces a copy of the whole
        // per-file dictionary on every committed cycle.
        let stalePaths = cache.compactMap { path, entry -> String? in
            entry.entries != nil && entry.modDate < today ? path : nil
        }
        for path in stalePaths {
            cache[path]?.entries = nil
        }
    }

    /// Exposes discovery for testing the symlink boundary check.
    func discoverJSONLFilesForTesting() -> [URL] {
        discoverJSONLFiles()
    }

    /// Force TTL expiry for testing — makes next discoverJSONLFiles() re-enumerate.
    func expireDiscoveryTTLForTesting() {
        lastFullEnumerationDate = .distantPast
        discoveredFiles = nil
    }

    /// Returns the number of per-file cache entries that still have live (non-nil) entry arrays.
    /// Used by tests to verify memory eviction behavior.
    func cacheEntriesWithLiveEntriesCountForTesting() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return cache.values.filter { $0.entries != nil }.count
    }

    // MARK: - Discovery

    private func discoverJSONLFiles() -> [URL] {
        // Fast path: nothing dirty and TTL not expired — return flattened cache
        if discoveredFiles != nil,
           !discoveryDirModDatesChanged(),
           let lastEnum = lastFullEnumerationDate,
           Date().timeIntervalSince(lastEnum) < Self.discoveryTTL {
            return discoveredFiles ?? []
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: projectsURL.path) else { return [] }

        // Determine if we must do a full enumeration (TTL expired) or can skip unchanged dirs
        let forceFullEnum = if let lastEnum = lastFullEnumerationDate,
                               Date().timeIntervalSince(lastEnum) < Self.discoveryTTL {
            false
        } else {
            true
        }

        var newDirModDates: [String: Date] = [:]

        // Track projects root mod date
        if let modDate = FileStat.modificationDate(of: projectsURL) {
            newDirModDates[projectsURL.path] = modDate
        }

        guard let projectDirs = try? fm.contentsOfDirectory(
            at: projectsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let resolvedBase = projectsURL.resolvingSymlinksInPath().path
        let resolvedBaseSlash = resolvedBase + "/"
        var currentDirPaths = Set<String>()

        for dir in projectDirs {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }

            // Every project directory counts — including sessions other tools write here
            // (e.g. claude-mem observer sessions under `-Users-x--claude-mem-...`). Claude
            // Code encodes both `/` and `.` as `-`, so a "decode and skip hidden path
            // components" filter can never match a real directory name; a deny-list
            // was considered and rejected (spec/DATA_LAYER.md, SessionLogReader).
            let dirPath = dir.path
            currentDirPaths.insert(dirPath)

            // Track directory mod date
            let dirModDate = FileStat.modificationDate(of: dir)
            if let md = dirModDate {
                newDirModDates[dirPath] = md
            }

            // Skip unchanged directories — use cached file list (unless forced full enumeration)
            if !forceFullEnum,
               let cachedDate = discoveryDirModDates[dirPath],
               let currentDate = dirModDate,
               currentDate == cachedDate,
               discoveredFilesByDir[dirPath] != nil {
                continue
            }

            // Enumerate this directory for JSONL files
            var dirFiles: [URL] = []
            if let enumerator = fm.enumerator(
                at: dir,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let fileURL as URL in enumerator {
                    if fileURL.pathExtension == "jsonl" {
                        // Symlink boundary + regular file check
                        let resolved = fileURL.resolvingSymlinksInPath().path
                        guard resolved == resolvedBase || resolved.hasPrefix(resolvedBaseSlash), (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
                        dirFiles.append(fileURL)
                    }
                }
            }
            discoveredFilesByDir[dirPath] = dirFiles
        }

        // Remove stale directory entries (deleted project dirs)
        let staleDirs = discoveredFilesByDir.keys.filter { !currentDirPaths.contains($0) }
        for key in staleDirs {
            discoveredFilesByDir.removeValue(forKey: key)
        }

        // Flatten all per-directory caches into the result
        let jsonlFiles = Array(discoveredFilesByDir.values.flatMap { $0 })

        discoveredFiles = jsonlFiles
        discoveryDirModDates = newDirModDates
        if forceFullEnum {
            lastFullEnumerationDate = Date()
        }
        return jsonlFiles
    }

    /// Check if any tracked directory mod dates have changed since last discovery.
    private func discoveryDirModDatesChanged() -> Bool {
        for (path, cachedDate) in discoveryDirModDates {
            guard let currentDate = FileStat.modificationDate(ofPath: path) else {
                return true // Can't stat → assume changed
            }
            if currentDate != cachedDate {
                return true
            }
        }
        return false
    }

    // MARK: - Streaming line reader

    /// What one parse of a session file produced.
    struct FileParse {
        var entries: [AssistantUsageEntry] = []
        /// Byte offset of the first line this parse did NOT fully consume — i.e. just
        /// past the last newline. A later parse resumes here.
        var resumeOffset: UInt64 = 0
        /// The entry produced by a final line with no trailing newline, if any.
        ///
        /// Claude Code is mid-write on that line: it is parsed (so the newest turn shows
        /// immediately) but `resumeOffset` stops *before* it, so the next parse sees it
        /// again. Recording what it contributed is what lets that contribution be undone
        /// before the re-parse, instead of counting the same tool calls twice.
        var trailing: TrailingContribution?

        struct TrailingContribution: Equatable {
            let messageId: String
            let toolCalls: Int
            /// True when the trailing line created the entry rather than coalescing into
            /// one an earlier line had already produced.
            let createdEntry: Bool
        }
    }

    /// Parse a session file, optionally resuming at a byte offset.
    ///
    /// `from` > 0 is the incremental path: only the bytes appended since the last parse
    /// are read. The caller is responsible for establishing that the file really is the
    /// same file, grown (see `tailParseOffset`).
    private func readSessionFile(at url: URL, from offset: UInt64 = 0) -> FileParse {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return FileParse() }
        defer { try? handle.close() }
        if offset > 0 {
            guard (try? handle.seek(toOffset: offset)) != nil else { return FileParse() }
        }
        var consumed = offset

        var entries: [AssistantUsageEntry] = []
        // Claude Code writes one JSONL line per content block, all sharing `message.id`
        // and carrying identical `usage`. The first line is usually text/thinking with
        // zero `tool_use` blocks; the cross-file dedup in `rebuild` keeps first-wins, so
        // without coalescing here the tool-call count was ~25x too low (187 → 7 on a
        // real file). Token fields are taken from the first line only.
        var indexById: [String: Int] = [:]
        let decoder = Self.jsonDecoder

        /// - Returns: whether this call created a new entry (rather than coalescing).
        @discardableResult
        func collect(_ entry: AssistantUsageEntry) -> Bool {
            if let index = indexById[entry.messageId] {
                if entry.toolCallCount > 0 {
                    entries[index] = Self.addingToolCalls(entry.toolCallCount, to: entries[index])
                }
                return false
            }
            indexById[entry.messageId] = entries.count
            entries.append(entry)
            return true
        }

        let bufferSize = 64 * 1_024 // 64KB chunks
        let maxLineSize = 1_048_576 // 1MB — skip lines longer than this (malformed/corrupt)
        var leftover = Data()
        /// Set once a line passes `maxLineSize` without a newline. Until the newline
        /// arrives every further byte is dropped — previously the remainder was
        /// re-counted as corrupt once per MB and its tail parsed as a new line.
        var skippingOversizedLine = false

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
                    consumed += UInt64(leftover.count)
                    leftover.removeAll()
                    continue
                }
                consumed += UInt64(newlineIndex - leftover.startIndex + 1)
                leftover = Data(leftover[(newlineIndex + 1)...])
                alreadyScanned = 0
                skippingOversizedLine = false
            } else if leftover.count > maxLineSize, leftover.firstNewlineIndex(from: leftover.startIndex + alreadyScanned) == nil {
                // Malformed / unexpectedly large line — count once, skip to its newline.
                corruptLineCounter.add(1)
                AppLogger.files.debug("Skipping oversized JSONL line (>\(leftover.count) bytes) in \(url.lastPathComponent, privacy: .public)")
                consumed += UInt64(leftover.count)
                leftover.removeAll()
                skippingOversizedLine = true
                continue
            }

            // Process complete lines (memchr-backed search, resumed where the last pass stopped)
            var searchFrom = leftover.startIndex + alreadyScanned
            while let newlineIndex = leftover.firstNewlineIndex(from: searchFrom) {
                let lineData = leftover[leftover.startIndex..<newlineIndex]
                // Everything up to and including this newline is now accounted for.
                consumed += UInt64(lineData.count + 1)
                leftover = leftover[(newlineIndex + 1)...]
                searchFrom = leftover.startIndex

                guard !lineData.isEmpty else { continue }

                // Fast pre-filter: check for markers without decoding
                let hasAssistant = Self.assistantMarkers.contains { lineData.range(of: $0) != nil }
                guard hasAssistant, lineData.range(of: Self.usageMarker) != nil else { continue }

                let decoded: SessionEntry
                do {
                    decoded = try decoder.decode(SessionEntry.self, from: Data(lineData))
                } catch {
                    corruptLineCounter.add(1)
                    AppLogger.files.debug("JSONL decode failed in \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    continue
                }
                if let usageEntry = Self.makeUsageEntry(from: decoded) {
                    collect(usageEntry)
                } else if Self.hasCorruptTimestamp(decoded) {
                    corruptLineCounter.add(1)
                    AppLogger.files.debug("JSONL line without a parseable timestamp skipped in \(url.lastPathComponent, privacy: .public)")
                }
            }

            // Compact leftover to drop reference to the old backing buffer.
            // Without this, slice chains keep the entire read buffer alive in memory.
            if leftover.startIndex != 0 {
                leftover = Data(leftover)
            }
        }

        // Process any remaining data without trailing newline.
        // Skip incomplete lines (no closing brace = partial write, likely still being written).
        var trailing: FileParse.TrailingContribution?
        if !skippingOversizedLine, !leftover.isEmpty,
           leftover.last == UInt8(ascii: "}") {
            let hasAssistant = Self.assistantMarkers.contains { leftover.range(of: $0) != nil }
            if hasAssistant, leftover.range(of: Self.usageMarker) != nil {
                let decoded: SessionEntry?
                do {
                    decoded = try decoder.decode(SessionEntry.self, from: Data(leftover))
                } catch {
                    AppLogger.files.debug("JSONL decode failed (trailing) in \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    decoded = nil
                }
                if let entry = decoded, let usageEntry = Self.makeUsageEntry(from: entry) {
                    let created = collect(usageEntry)
                    trailing = FileParse.TrailingContribution(
                        messageId: usageEntry.messageId,
                        toolCalls: usageEntry.toolCallCount,
                        createdEntry: created
                    )
                }
            }
        }

        return FileParse(entries: entries, resumeOffset: consumed, trailing: trailing)
    }

    /// The line's top-level ISO 8601 timestamp (fractional or whole seconds), or nil.
    nonisolated static func parseTimestamp(_ text: String?) -> Date? {
        text.flatMap(DateFormatters.parseISO8601)
    }

    /// True for a line that is an assistant usage line in every respect except its
    /// timestamp — the one reason `makeUsageEntry` returns nil that counts as corrupt.
    private static func hasCorruptTimestamp(_ entry: SessionEntry) -> Bool {
        entry.type == "assistant" && entry.message?.usage != nil && entry.message?.model != nil
            && parseTimestamp(entry.timestamp) == nil
    }

    /// Copy of `entry` with `count` more tool calls — used to fold a later content-block
    /// line of the same message into the entry built from its first line.
    /// `count` may be negative: undoing a trailing line's contribution before re-reading it.
    static func addingToolCalls(_ count: Int, to entry: AssistantUsageEntry) -> AssistantUsageEntry {
        AssistantUsageEntry(
            timestamp: entry.timestamp,
            model: entry.model,
            messageId: entry.messageId,
            inputTokens: entry.inputTokens,
            outputTokens: entry.outputTokens,
            cacheReadTokens: entry.cacheReadTokens,
            cacheWriteTokens: entry.cacheWriteTokens,
            sessionId: entry.sessionId,
            cwd: entry.cwd,
            gitBranch: entry.gitBranch,
            toolCallCount: entry.toolCallCount + count,
            contextWindow: entry.contextWindow,
            reasoningTokens: entry.reasoningTokens,
            effortLabel: entry.effortLabel,
            creatorAccountId: entry.creatorAccountId
        )
    }

    /// Build an `AssistantUsageEntry` from a decoded session entry, or nil if it's not an assistant message with usage.
    nonisolated static func makeUsageEntry(from entry: SessionEntry) -> AssistantUsageEntry? {
        guard entry.type == "assistant",
              let message = entry.message,
              let usage = message.usage,
              let model = message.model else { return nil }

        // Stable fallback: deterministic composite key so re-reading the same file
        // after cache eviction produces the same ID (preserving deduplication).
        let messageId = message.id ?? entry.uuid
            ?? "\(entry.sessionId ?? ""):\(entry.timestamp ?? ""):\(usage.inputTokens ?? 0):\(usage.outputTokens ?? 0)"
        // Either ISO 8601 shape; a missing / malformed stamp is a corrupt line, never
        // "now" — a `Date()` fallback drops a historical message into the current 5h /
        // 7d windows and today's chart during a cold scan (mirrors CodexSessionLogParser).
        guard let timestamp = Self.parseTimestamp(entry.timestamp) else { return nil }

        let toolCallCount = message.content?.filter { $0.type == "tool_use" }.count ?? 0

        let output = usage.outputTokens ?? 0
        let thinking = min(max(usage.outputTokensDetails?.thinkingTokens ?? 0, 0), output)
        let speed = usage.speed?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let effort: String? = (speed == nil || speed == "standard" || speed == "") ? nil : speed

        return AssistantUsageEntry(
            timestamp: timestamp,
            model: model,
            messageId: messageId,
            inputTokens: usage.inputTokens ?? 0,
            outputTokens: usage.outputTokens ?? 0,
            cacheReadTokens: usage.cacheReadInputTokens ?? 0,
            cacheWriteTokens: usage.cacheCreationInputTokens ?? 0,
            sessionId: entry.sessionId ?? "",
            cwd: entry.cwd,
            gitBranch: entry.gitBranch,
            toolCallCount: toolCallCount,
            contextWindow: nil,
            reasoningTokens: thinking,
            effortLabel: effort
        )
    }
}
