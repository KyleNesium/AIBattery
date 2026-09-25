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

    nonisolated static func latestRateLimits(sessionsRoot: URL = CodexPaths.sessions) -> (rateLimits: RateLimitUsage, asOf: Date)? {
        guard let file = newestSessionFile(in: sessionsRoot),
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

    nonisolated static func newestSessionFile(in root: URL, fileManager: FileManager = .default) -> URL? {
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return nil
        }
        var newest: (url: URL, date: Date)?
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
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
            guard let line = String(data: lineData, encoding: .utf8),
                  line.contains("\"rate_limits\"") else { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let payload = obj["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count",
                  let rateLimits = payload["rate_limits"] as? [String: Any] else { continue }
            return CodexUsageParser.parseSessionRateLimits(rateLimits)
        }
        return nil
    }
}
