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
    }

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

    private nonisolated(unsafe) static let isoFormatter = DateFormatters.iso8601

    /// Pre-computed byte markers for fast JSONL pre-filtering (avoids re-allocating per file).
    private static let assistantMarkers: [Data] = [
        "\"type\":\"assistant\"",
        "\"type\": \"assistant\"",
    ].compactMap { $0.data(using: .utf8) }
    private static let usageMarker: Data = "\"usage\"".data(using: .utf8) ?? Data()
    /// Shared decoder — avoids allocating a new one per JSONL file.
    private static let jsonDecoder = JSONDecoder()

    /// Number of corrupt/skipped lines from the most recent file parse cycle.
    private(set) var lastCorruptLineCount = 0

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
            // Clear lastFullEnumerationDate so next call does per-dir check (not TTL shortcut).
            lastFullEnumerationDate = nil
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
        lastCorruptLineCount = 0

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
            }
        }

        // Incremental rebuild: use cachedAllEntries as base, only re-parse changed/new files.
        // For evicted files with unchanged fingerprint, entries already live in cachedAllEntries.
        let result = rebuild(jsonlFiles: jsonlFiles, base: cachedAllEntries)

        if pendingInvalidation.swap(false) {
            isDirty = true
            lock.unlock()
            return result
        }

        cachedAllEntries = result
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
    private func rebuild(jsonlFiles: [URL], base: [AssistantUsageEntry]?) -> [AssistantUsageEntry] {
        var resultEntries = base ?? []
        var seenIds = Set(resultEntries.map(\.messageId))
        var changed = false

        for fileURL in jsonlFiles {
            let path = fileURL.path
            let fm = FileManager.default

            let attrs = try? fm.attributesOfItem(atPath: path)
            let modDate = attrs?[.modificationDate] as? Date
            let fileSize = attrs?[.size] as? UInt64

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

            // Re-parse (or first-parse for new files).
            let entries = readSessionFile(at: fileURL)
            let newIds = Set(entries.map(\.messageId))
            cache[path] = FileCacheEntry(
                modDate: modDate ?? Date(),
                fileSize: fileSize ?? 0,
                entries: entries,
                messageIds: newIds
            )
            for entry in entries {
                if seenIds.insert(entry.messageId).inserted {
                    resultEntries.append(entry)
                    changed = true
                }
            }
        }

        if changed || base == nil {
            resultEntries.sort { $0.timestamp < $1.timestamp }
        }
        return resultEntries
    }

    /// Release raw entry arrays from per-file cache for files not modified today.
    /// Only the fingerprint (modDate + fileSize) and messageIds are retained.
    /// cachedAllEntries remains the authoritative source for these entries.
    private func evictOldFileEntries() {
        let today = Calendar.current.startOfDay(for: Date())
        for (path, entry) in cache where entry.entries != nil && entry.modDate < today {
            cache[path] = FileCacheEntry(
                modDate: entry.modDate,
                fileSize: entry.fileSize,
                entries: nil,
                messageIds: entry.messageIds
            )
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
        if let attrs = try? fm.attributesOfItem(atPath: projectsURL.path),
           let modDate = attrs[.modificationDate] as? Date {
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

            // Skip non-Claude-Code project directories (e.g. MCP observer sessions).
            // Claude Code encodes the project's absolute path as the directory name,
            // replacing "/" with "-". Decode back to a path and check if any component
            // starts with "." (hidden directory).
            let decodedPath = "/" + dir.lastPathComponent.dropFirst().replacingOccurrences(of: "-", with: "/")
            if decodedPath.split(separator: "/").contains(where: { $0.hasPrefix(".") }) {
                continue
            }

            let dirPath = dir.path
            currentDirPaths.insert(dirPath)

            // Track directory mod date
            let dirModDate: Date?
            if let attrs = try? fm.attributesOfItem(atPath: dirPath) {
                dirModDate = attrs[.modificationDate] as? Date
                if let md = dirModDate {
                    newDirModDates[dirPath] = md
                }
            } else {
                dirModDate = nil
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
                        guard resolved == resolvedBase || resolved.hasPrefix(resolvedBaseSlash) else { continue }
                        guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
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
        let fm = FileManager.default
        for (path, cachedDate) in discoveryDirModDates {
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  let currentDate = attrs[.modificationDate] as? Date else {
                return true // Can't stat → assume changed
            }
            if currentDate != cachedDate {
                return true
            }
        }
        return false
    }

    // MARK: - Streaming line reader

    private func readSessionFile(at url: URL) -> [AssistantUsageEntry] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        var entries: [AssistantUsageEntry] = []
        let decoder = Self.jsonDecoder

        let bufferSize = 64 * 1_024 // 64KB chunks
        let maxLineSize = 1_048_576 // 1MB — skip lines longer than this (malformed/corrupt)
        var leftover = Data()

        while true {
            guard let chunk = try? handle.read(upToCount: bufferSize), !chunk.isEmpty else { break }
            leftover.append(chunk)

            // Safety: if leftover exceeds max line size without finding a newline,
            // the JSONL line is malformed — discard and move on.
            if leftover.count > maxLineSize, leftover.firstIndex(of: UInt8(ascii: "\n")) == nil {
                lastCorruptLineCount += 1
                AppLogger.files.warning("Skipping oversized JSONL line (\(leftover.count) bytes) in \(url.lastPathComponent, privacy: .public)")
                leftover.removeAll()
                continue
            }

            // Process complete lines
            while let newlineIndex = leftover.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = leftover[leftover.startIndex..<newlineIndex]
                leftover = leftover[(newlineIndex + 1)...]

                guard !lineData.isEmpty else { continue }

                // Fast pre-filter: check for markers without decoding
                let hasAssistant = Self.assistantMarkers.contains { lineData.range(of: $0) != nil }
                guard hasAssistant, lineData.range(of: Self.usageMarker) != nil else { continue }

                let decoded: SessionEntry
                do {
                    decoded = try decoder.decode(SessionEntry.self, from: Data(lineData))
                } catch {
                    lastCorruptLineCount += 1
                    AppLogger.files.debug("JSONL decode failed in \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    continue
                }
                if let usageEntry = Self.makeUsageEntry(from: decoded) {
                    entries.append(usageEntry)
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
        if !leftover.isEmpty,
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
                    entries.append(usageEntry)
                }
            }
        }

        return entries
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
        let timestamp: Date = if let ts = entry.timestamp {
            isoFormatter.date(from: ts) ?? Date()
        } else {
            Date()
        }

        let toolCallCount = message.content?.filter { $0.type == "tool_use" }.count ?? 0

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
            toolCallCount: toolCallCount
        )
    }
}
