import Foundation
import os

final class SessionLogReader {
    static let shared = SessionLogReader()

    private var projectsURL: URL { ClaudePaths.projects }

    // Cache: filePath -> (modDate, fileSize, entries)
    private var cache: [String: (Date, UInt64, [AssistantUsageEntry])] = [:]

    /// Maximum number of cached files before eviction.
    private let maxCacheEntries = 200

    /// Cached result of readAllUsageEntries — invalidated when any file changes.
    private var cachedAllEntries: [AssistantUsageEntry]?

    /// Cached list of discovered JSONL file URLs.
    private var discoveredFiles: [URL]?
    /// Parent directory mod dates used to invalidate discovery cache.
    private var discoveryDirModDates: [String: Date] = [:]

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Number of corrupt/skipped lines from the most recent file parse cycle.
    private(set) var lastCorruptLineCount = 0

    /// Called by FileWatcher when files change — invalidates caches so the next read re-scans.
    func invalidate() {
        cachedAllEntries = nil
        discoveredFiles = nil
        discoveryDirModDates.removeAll()
    }

    func readAllUsageEntries() -> [AssistantUsageEntry] {
        // Return cached result if available (invalidated by FileWatcher)
        if let cached = cachedAllEntries { return cached }

        lastCorruptLineCount = 0
        let jsonlFiles = discoverJSONLFiles()
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
        cachedAllEntries = allEntries
        return allEntries
    }

    func readTodayEntries() -> [AssistantUsageEntry] {
        let today = Calendar.current.startOfDay(for: Date())
        return readAllUsageEntries().filter { $0.timestamp >= today }
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

        // Evict oldest entries when cache grows too large
        if cache.count > maxCacheEntries {
            evictCache()
        }

        return entries
    }

    /// Evict oldest cache entries (by mod date) to stay under the limit.
    /// Batch-sorts once to avoid O(n²) from repeated min-find.
    private func evictCache() {
        let overflow = cache.count - maxCacheEntries
        guard overflow > 0 else { return }
        let toRemove = cache.sorted { $0.value.0 < $1.value.0 }.prefix(overflow)
        for entry in toRemove {
            cache.removeValue(forKey: entry.key)
        }
    }

    // MARK: - Discovery

    private func discoverJSONLFiles() -> [URL] {
        // Return cached discovery if directory mod dates haven't changed
        if let cached = discoveredFiles, !discoveryDirModDatesChanged() {
            return cached
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
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }

            // Track each project dir mod date
            if let attrs = try? fm.attributesOfItem(atPath: dir.path),
               let modDate = attrs[.modificationDate] as? Date {
                newDirModDates[dir.path] = modDate
            }

            if let files = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
                jsonlFiles.append(contentsOf: files.filter { $0.pathExtension == "jsonl" })
            }

            let subagentsDir = dir.appendingPathComponent("subagents")
            if let files = try? fm.contentsOfDirectory(
                at: subagentsDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
                jsonlFiles.append(contentsOf: files.filter { $0.pathExtension == "jsonl" })
            }
        }

        discoveredFiles = jsonlFiles
        discoveryDirModDates = newDirModDates
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
        let decoder = JSONDecoder()
        // Pre-filter markers for fast scanning without full JSON decode.
        // Check both compact and spaced variants of the type field.
        let assistantMarkers: [Data] = [
            "\"type\":\"assistant\"",
            "\"type\": \"assistant\"",
        ].compactMap { $0.data(using: .utf8) }
        let usageMarker = "\"usage\"".data(using: .utf8) ?? Data()

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
                let hasAssistant = assistantMarkers.contains { lineData.range(of: $0) != nil }
                guard hasAssistant, lineData.range(of: usageMarker) != nil else { continue }

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
        }

        // Process any remaining data without trailing newline.
        // Skip incomplete lines (no closing brace = partial write, likely still being written).
        if !leftover.isEmpty,
           leftover.last == UInt8(ascii: "}") {
            let hasAssistant = assistantMarkers.contains { leftover.range(of: $0) != nil }
            if hasAssistant, leftover.range(of: usageMarker) != nil {
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
    private static func makeUsageEntry(from entry: SessionEntry) -> AssistantUsageEntry? {
        guard entry.type == "assistant",
              let message = entry.message,
              let usage = message.usage,
              let model = message.model else { return nil }

        let messageId = message.id ?? entry.uuid ?? UUID().uuidString
        let timestamp: Date
        if let ts = entry.timestamp {
            timestamp = isoFormatter.date(from: ts) ?? Date()
        } else {
            timestamp = Date()
        }

        return AssistantUsageEntry(
            timestamp: timestamp,
            model: model,
            messageId: messageId,
            inputTokens: usage.input_tokens ?? 0,
            outputTokens: usage.output_tokens ?? 0,
            cacheReadTokens: usage.cache_read_input_tokens ?? 0,
            cacheWriteTokens: usage.cache_creation_input_tokens ?? 0,
            sessionId: entry.sessionId ?? "",
            cwd: entry.cwd,
            gitBranch: entry.gitBranch
        )
    }
}
