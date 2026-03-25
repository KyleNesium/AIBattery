import Foundation
import os

/// Reads and caches JSONL session log files. NOT MainActor — file I/O must not block the UI.
/// Thread-safety: mutable state accessed behind `lock`. `invalidate()` uses `tryLock` so
/// FileWatcher on main never blocks waiting for a long-running background scan.
final class SessionLogReader: @unchecked Sendable {
    private let lock = NSLock()
    /// Set true by invalidate() when lock is held by a scan — checked after scan completes.
    private var pendingInvalidation = false
    static let shared = SessionLogReader()

    private let projectsURL: URL

    init(projectsURL: URL? = nil) {
        self.projectsURL = projectsURL ?? ClaudePaths.projects
    }

    // Cache: filePath -> (modDate, fileSize, entries)
    private var cache: [String: (Date, UInt64, [AssistantUsageEntry])] = [:]

    /// Dirty flag — set by invalidate(), cleared by readAllUsageEntries().
    /// Starts true so the first read performs a full scan.
    private var isDirty = true

    /// Maximum time between full directory enumerations, regardless of mod-date changes.
    /// Catches new files on filesystems where directory mtime doesn't always update.
    static let discoveryTTL: TimeInterval = 60

    /// Cached result of readAllUsageEntries — invalidated when any file changes.
    private var cachedAllEntries: [AssistantUsageEntry]?

    /// Cached list of discovered JSONL file URLs.
    private var discoveredFiles: [URL]?
    /// Parent directory mod dates used to invalidate discovery cache.
    private var discoveryDirModDates: [String: Date] = [:]
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
    /// Does NOT clear per-file cache — unchanged files keep their cached entries (fingerprint handles staleness).
    func invalidate() {
        if lock.try() {
            isDirty = true
            // Clear discovery cache so new/deleted files are found
            discoveredFiles = nil
            discoveryDirModDates.removeAll()
            lastFullEnumerationDate = nil
            lock.unlock()
        } else {
            // Scan in progress — mark for invalidation when it finishes
            pendingInvalidation = true
        }
    }

    func readAllUsageEntries() -> [AssistantUsageEntry] {
        lock.lock()
        pendingInvalidation = false
        lastCorruptLineCount = 0

        // Fast path: not dirty, return cached result
        if !isDirty, let cached = cachedAllEntries {
            lock.unlock()
            return cached
        }

        isDirty = false
        let jsonlFiles = discoverJSONLFiles()

        // Remove cache entries for files that no longer exist
        let currentPaths = Set(jsonlFiles.map(\.path))
        let staleKeys = cache.keys.filter { !currentPaths.contains($0) }
        for key in staleKeys { cache.removeValue(forKey: key) }

        // Incremental rebuild: cachedRead returns instantly for unchanged files (fingerprint match)
        var allEntries: [AssistantUsageEntry] = []
        var seenMessageIds = Set<String>()

        for fileURL in jsonlFiles {
            let entries = cachedRead(fileURL)
            for entry in entries {
                if seenMessageIds.insert(entry.messageId).inserted {
                    allEntries.append(entry)
                }
            }
        }

        allEntries.sort { $0.timestamp < $1.timestamp }

        // If invalidate() was called during the scan, discard cache so next call re-scans.
        if pendingInvalidation {
            pendingInvalidation = false
            isDirty = true
            lock.unlock()
            return allEntries
        }
        cachedAllEntries = allEntries
        lock.unlock()
        return allEntries
    }

    // MARK: - Caching

    private func cachedRead(_ url: URL) -> [AssistantUsageEntry] {
        let path = url.path
        let fm = FileManager.default

        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let modDate = attrs[.modificationDate] as? Date,
              let fileSize = attrs[.size] as? UInt64 else {
            return readSessionFile(at: url)
        }

        if let cached = cache[path], cached.0 == modDate, cached.1 == fileSize {
            return cached.2
        }

        let entries = readSessionFile(at: url)
        cache[path] = (modDate, fileSize, entries)
        return entries
    }

    /// Exposes discovery for testing the symlink boundary check.
    func discoverJSONLFilesForTesting() -> [URL] {
        discoverJSONLFiles()
    }

    /// Force TTL expiry for testing — makes next discoverJSONLFiles() re-enumerate.
    func expireDiscoveryTTLForTesting() {
        lastFullEnumerationDate = .distantPast
    }

    // MARK: - Discovery

    private func discoverJSONLFiles() -> [URL] {
        // Return cached discovery if directory mod dates haven't changed AND TTL hasn't expired
        if let cached = discoveredFiles, !discoveryDirModDatesChanged() {
            if let lastEnum = lastFullEnumerationDate,
               Date().timeIntervalSince(lastEnum) < Self.discoveryTTL {
                return cached
            }
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: projectsURL.path) else { return [] }

        var jsonlFiles: [URL] = []
        var newDirModDates: [String: Date] = [:]

        // Track projects dir mod date
        if let attrs = try? fm.attributesOfItem(atPath: projectsURL.path),
           let modDate = attrs[.modificationDate] as? Date {
            newDirModDates[projectsURL.path] = modDate
        }

        guard let projectDirs = try? fm.contentsOfDirectory(
            at: projectsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        for dir in projectDirs {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }

            // Skip non-Claude-Code project directories (e.g. MCP observer sessions).
            // Claude Code encodes the project's absolute path as the directory name,
            // replacing "/" with "-". Decode back to a path and check if any component
            // starts with "." (hidden directory). This avoids false positives on project
            // directories that legitimately contain double hyphens (e.g. "my--project").
            let decodedPath = "/" + dir.lastPathComponent.dropFirst().replacingOccurrences(of: "-", with: "/")
            if decodedPath.split(separator: "/").contains(where: { $0.hasPrefix(".") }) { continue }

            // Track each project dir mod date
            if let attrs = try? fm.attributesOfItem(atPath: dir.path),
               let modDate = attrs[.modificationDate] as? Date {
                newDirModDates[dir.path] = modDate
            }

            // Enumerate all JSONL files recursively (top-level + session dirs + subagents)
            // using a single enumerator instead of per-directory contentsOfDirectory calls.
            if let enumerator = fm.enumerator(
                at: dir,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let fileURL as URL in enumerator {
                    if fileURL.pathExtension == "jsonl" {
                        jsonlFiles.append(fileURL)
                    }
                }
            }
        }

        // Symlink boundary + regular file check in a single pass.
        // Rejects symlinks escaping the projects directory and non-regular files (pipes, devices, sockets).
        let resolvedBase = projectsURL.resolvingSymlinksInPath().path
        let resolvedBaseSlash = resolvedBase + "/"
        jsonlFiles = jsonlFiles.filter {
            let resolved = $0.resolvingSymlinksInPath().path
            guard resolved == resolvedBase || resolved.hasPrefix(resolvedBaseSlash) else { return false }
            return (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
        }

        discoveredFiles = jsonlFiles
        discoveryDirModDates = newDirModDates
        lastFullEnumerationDate = Date()
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
            if currentDate != cachedDate { return true }
        }
        return false
    }

    // MARK: - Streaming line reader

    private func readSessionFile(at url: URL) -> [AssistantUsageEntry] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        var entries: [AssistantUsageEntry] = []
        let decoder = Self.jsonDecoder

        let bufferSize = 64 * 1024 // 64KB chunks
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
        // after LRU cache eviction produces the same ID (preserving deduplication).
        let messageId = message.id ?? entry.uuid
            ?? "\(entry.sessionId ?? ""):\(entry.timestamp ?? ""):\(usage.inputTokens ?? 0):\(usage.outputTokens ?? 0)"
        let timestamp: Date
        if let ts = entry.timestamp {
            timestamp = isoFormatter.date(from: ts) ?? Date()
        } else {
            timestamp = Date()
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
