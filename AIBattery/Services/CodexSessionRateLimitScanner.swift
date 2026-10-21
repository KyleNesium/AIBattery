import Foundation

/// Fallback rate-limit source: the Codex CLI writes a `rate_limits` snapshot
/// into every `token_count` event in its session logs. When the wham/usage
/// endpoint is unreachable, the newest session file's last snapshot is the
/// best local truth. Always surfaced as CACHED data (alarm-suppressed) —
/// it's as old as the user's last Codex turn.
enum CodexSessionRateLimitScanner {
    /// How much of the file tail to scan. token_count events recur every few
    /// turns; 256 KB of tail reliably contains several.
    private static let tailBytes = 256 * 1_024

    /// How long a `newestSessionFile` result is reused. This path runs on every poll for
    /// as long as the usage endpoint is in backoff (60s–5min), and a poll can be as
    /// frequent as every 10s, so without a TTL an outage means walking the whole
    /// `~/.codex/sessions` tree every few seconds. The newest *file* changes only when the
    /// CLI starts a session; its contents are re-read on every call regardless.
    private static let newestFileCacheTTL: TimeInterval = 60

    private static let newestFileCacheLock = NSLock()
    nonisolated(unsafe) private static var newestFileCache: (root: URL, url: URL?, at: Date)?

    nonisolated static func latestRateLimits(sessionsRoot: URL = CodexPaths.sessions) -> (rateLimits: RateLimitUsage, asOf: Date)? {
        guard let file = cachedNewestSessionFile(in: sessionsRoot),
              let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(),
              let usage = extractLatestRateLimits(fromTail: data) else { return nil }
        let attrs = try? FileManager.default.attributesOfItem(atPath: file.path)
        let modDate = attrs?[.modificationDate] as? Date ?? Date()
        return (usage, modDate)
    }

    /// `newestSessionFile` behind the TTL. Call sites that want a guaranteed-fresh walk
    /// (tests) use `newestSessionFile` directly.
    nonisolated static func cachedNewestSessionFile(in root: URL, now: Date = .now) -> URL? {
        newestFileCacheLock.lock()
        defer { newestFileCacheLock.unlock() }
        if let cache = newestFileCache, cache.root == root, now.timeIntervalSince(cache.at) < newestFileCacheTTL {
            return cache.url
        }
        let url = newestSessionFile(in: root)
        newestFileCache = (root, url, now)
        return url
    }

    /// Drop the memoized directory walk. Called when the Codex session tree changes
    /// underneath us (watcher invalidation) and from tests.
    nonisolated static func invalidateFileCache() {
        newestFileCacheLock.lock()
        newestFileCache = nil
        creatorIdCache = nil
        newestFileCacheLock.unlock()
    }

    /// Cap on the first line of a rollout. `session_meta` carries `base_instructions`
    /// (observed up to 23 KB); the reader discards lines over 1 MB, so do we.
    static let sessionMetaMaxLineBytes = 1_048_576

    nonisolated(unsafe) private static var creatorIdCache: (file: URL, id: String?)?

    /// The ChatGPT account stamped on the newest rollout, or nil. Memoized per newest
    /// file (the file changes only when the CLI starts a session; its first line never
    /// changes after that), so an outage costs one head read per session, not per poll.
    nonisolated static func creatorAccountId(ofNewestIn root: URL = CodexPaths.sessions, now: Date = .now) -> String? {
        guard let file = cachedNewestSessionFile(in: root, now: now) else { return nil }
        newestFileCacheLock.lock()
        defer { newestFileCacheLock.unlock() }
        if let cache = creatorIdCache, cache.file == file {
            return cache.id
        }
        let id = creatorAccountId(fromFirstLineOf: file)
        creatorIdCache = (file, id)
        return id
    }

    /// Reads the file's first line only. Same content boundary as everywhere else: a
    /// `response_item` is rejected from its head bytes and never decoded; only a line
    /// whose `type` is `session_meta` yields a value, and only `creator_account_id` is read.
    nonisolated static func creatorAccountId(fromFirstLineOf file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: sessionMetaMaxLineBytes + 1), !head.isEmpty else { return nil }
        let line: Data
        if let lineEnd = head.firstNewlineIndex(from: head.startIndex) {
            line = head[head.startIndex..<lineEnd]
        } else if head.count <= sessionMetaMaxLineBytes {
            // Read hit EOF, not the cap: the whole file is one unterminated line (the
            // common case for a session_meta line written just before this read).
            line = head
        } else {
            // Got cap+1 bytes with no newline inside: the line is over the cap.
            return nil
        }
        guard !CodexSessionLogParser.isResponseItem(line),
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "session_meta",
              let payload = object["payload"] as? [String: Any],
              let id = payload["creator_account_id"] as? String, !id.isEmpty else { return nil }
        return id
    }

    nonisolated static func newestSessionFile(in root: URL, fileManager: FileManager = .default) -> URL? {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        // Same symlink boundary as CodexSessionLogReader: a link inside ~/.codex/sessions
        // must not make us read (and JSON-parse the tail of) an arbitrary file.
        let resolvedBase = root.resolvingSymlinksInPath().path
        let resolvedBaseSlash = resolvedBase.hasSuffix("/") ? resolvedBase : resolvedBase + "/"
        var newest: (url: URL, date: Date)?
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let resolved = url.resolvingSymlinksInPath().path
            guard resolved == resolvedBase || resolved.hasPrefix(resolvedBaseSlash), (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if newest == nil || date > newest!.date {
                newest = (url.standardizedFileURL, date)
            }
        }
        return newest?.url
    }

    nonisolated static func extractLatestRateLimits(fromTail data: Data) -> RateLimitUsage? {
        // Split on 0x0A bytes BEFORE UTF-8 decoding: the tail seek can land mid
        // multi-byte character, and decoding the whole buffer at once would fail
        // outright. Per-line decode confines the damage to the partial first line.
        for lineData in data.split(separator: UInt8(ascii: "\n")).reversed() {
            // Same content boundary as the parser: a response_item (message content)
            // is rejected from its head bytes and never deserialized, even if its text
            // mentions "rate_limits".
            guard !CodexSessionLogParser.isResponseItem(lineData),
                  let line = String(data: lineData, encoding: .utf8),
                  line.contains("\"rate_limits\""), let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let payload = obj["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count",
                  let rateLimits = payload["rate_limits"] as? [String: Any] else { continue }
            return CodexUsageParser.parseSessionRateLimits(rateLimits)
        }
        return nil
    }
}
