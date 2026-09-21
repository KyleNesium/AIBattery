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

    /// Maximum time between directory enumerations. The nested date directories make
    /// per-directory mtimes a poor "new file" signal, so discovery is TTL + root-mtime.
    static let discoveryTTL: TimeInterval = 60
    private var discoveredFiles: [URL]?
    private var lastEnumerationDate: Date?
    private var rootModDateAtEnumeration: Date?

    /// Corrupt / skipped line count from the most recent `readAllUsageEntries()`.
    private(set) var lastCorruptLineCount = 0

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
        lastCorruptLineCount = 0

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
            }
        }

        let result = rebuild(files: files, base: cachedAllEntries)

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

    // MARK: - Rebuild / eviction

    private func rebuild(files: [URL], base: [AssistantUsageEntry]?) -> [AssistantUsageEntry] {
        var resultEntries = base ?? []
        var seenIds = Set(resultEntries.map(\.messageId))
        var changed = false
        let fm = FileManager.default

        for fileURL in files {
            let path = fileURL.path
            let attrs = try? fm.attributesOfItem(atPath: path)
            let modDate = attrs?[.modificationDate] as? Date
            let fileSize = attrs?[.size] as? UInt64

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
        return resultEntries
    }

    /// Release raw entry arrays for files not modified today — fingerprints and
    /// message IDs stay so a later change can still purge the file's stale entries.
    private func evictOldFileEntries() {
        let today = Calendar.current.startOfDay(for: Date())
        for (path, entry) in cache where entry.entries != nil && entry.modDate < today {
            cache[path] = FileCacheEntry(modDate: entry.modDate, fileSize: entry.fileSize, entries: nil, messageIds: entry.messageIds)
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

        let rootModDate = (try? fm.attributesOfItem(atPath: sessionsURL.path))?[.modificationDate] as? Date
        if let cached = discoveredFiles,
           let lastEnum = lastEnumerationDate,
           Date().timeIntervalSince(lastEnum) < Self.discoveryTTL,
           rootModDate == rootModDateAtEnumeration {
            return cached
        }

        let resolvedBase = sessionsURL.resolvingSymlinksInPath().path
        let resolvedBaseSlash = resolvedBase + "/"
        var files: [URL] = []

        if let enumerator = fm.enumerator(
            at: sessionsURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
                // Symlink boundary: a link inside ~/.codex/sessions must not read arbitrary files.
                let resolved = fileURL.resolvingSymlinksInPath().path
                guard resolved == resolvedBase || resolved.hasPrefix(resolvedBaseSlash) else { continue }
                guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
                files.append(fileURL)
            }
        }

        discoveredFiles = files
        lastEnumerationDate = Date()
        rootModDateAtEnumeration = rootModDate
        return files
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

        func process(_ lineData: Data) {
            defer { lineIndex += 1 }
            guard !lineData.isEmpty, CodexSessionLogParser.mightBeRelevant(lineData) else { return }
            if let entry = parser.consume(line: lineData, lineIndex: lineIndex) {
                entries.append(entry)
            }
        }

        while true {
            guard let chunk = try? handle.read(upToCount: bufferSize), !chunk.isEmpty else { break }
            leftover.append(chunk)

            if leftover.count > maxLineSize, leftover.firstIndex(of: UInt8(ascii: "\n")) == nil {
                lastCorruptLineCount += 1
                AppLogger.files.warning("Skipping oversized Codex JSONL line (\(leftover.count) bytes) in \(url.lastPathComponent, privacy: .public)")
                leftover.removeAll()
                continue
            }

            while let newlineIndex = leftover.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = Data(leftover[leftover.startIndex..<newlineIndex])
                leftover = leftover[(newlineIndex + 1)...]
                process(lineData)
            }

            // Compact so slice chains don't pin the whole read buffer.
            if leftover.startIndex != 0 {
                leftover = Data(leftover)
            }
        }

        // Trailing data without a newline: only a complete object (ends with `}`) is a
        // finished line — anything else is a partial write still in progress.
        if !leftover.isEmpty, leftover.last == UInt8(ascii: "}") {
            process(Data(leftover))
        }

        lastCorruptLineCount += parser.corruptLineCount
        return entries
    }
}
