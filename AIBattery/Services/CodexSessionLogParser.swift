import Foundation

/// Per-file state machine that turns Codex CLI rollout JSONL lines into
/// `AssistantUsageEntry` values (design spec §4). One instance per file parse;
/// not thread-safe by itself — `CodexSessionLogReader` owns it under its lock.
///
/// Only three line types are ever inspected:
///   - `session_meta`  → session identity (id, cwd, git branch)
///   - `turn_context`  → the model in effect for subsequent turns
///   - `event_msg` / `payload.type == "token_count"` → one entry per turn from
///     `info.last_token_usage` (never the cumulative `total_token_usage`, which
///     would double-count exactly like the stats-cache hazard on the Claude side)
///
/// Everything else — notably `response_item`, which carries message content — is
/// rejected on `type` alone; its `payload` is never read. Token counts only.
struct CodexSessionLogParser {
    private(set) var sessionId: String?
    private(set) var cwd: String?
    private(set) var gitBranch: String?
    /// Model from the most recent `turn_context`. A `token_count` seen before any
    /// `turn_context` cannot be attributed to a model and is skipped (not corrupt).
    private(set) var currentModel: String?
    /// Lines that looked relevant but failed to decode as JSON objects.
    private(set) var corruptLineCount = 0
    /// Cumulative `info.total_token_usage` of the last entry emitted for this file.
    /// Codex re-emits `token_count` with unchanged, non-null `info` when it refreshes
    /// rate limits (measured: ~7% of real `token_count` events, ~10% of the tokens in
    /// a local rollout tree). Each repeat carries a new `ordinal`, so the reader's
    /// `messageId` dedup cannot catch it and the same turn is counted again. A turn
    /// that produced tokens always advances the cumulative total, so an unchanged
    /// total means "nothing new happened".
    private var lastTotalUsage: TotalUsage?

    /// The cumulative counters compared to decide whether a `token_count` repeats
    /// the previous one. Value type so the comparison is exact and allocation-free.
    private struct TotalUsage: Equatable {
        let input: Int
        let cached: Int
        let cacheWrite: Int
        let output: Int

        init?(_ total: Any?) {
            guard let total = total as? [String: Any] else { return nil }
            input = CodexSessionLogParser.int(total["input_tokens"])
            cached = CodexSessionLogParser.int(total["cached_input_tokens"])
            cacheWrite = CodexSessionLogParser.int(total["cache_write_input_tokens"])
            output = CodexSessionLogParser.int(total["output_tokens"])
        }
    }

    /// Used for `sessionId` when the file has no `session_meta` line (the file
    /// name stem — stable across re-parses so message IDs stay deterministic).
    let fallbackSessionId: String

    init(fallbackSessionId: String) {
        self.fallbackSessionId = fallbackSessionId
    }

    private static let relevantMarkers: [Data] = [
        "\"session_meta\"", "\"turn_context\"", "\"token_count\"",
    ].compactMap { $0.data(using: .utf8) }

    /// How much of a line the pre-filter inspects. Rollout lines carry `type` (and
    /// `payload.type`) within the first ~100 bytes, so scanning the head is enough —
    /// and it keeps multi-megabyte `response_item` lines from being scanned end to end
    /// (the cold scan of a 340 MB tree dropped from ~15 s with whole-line scanning).
    static let relevanceHeadBytes = 512

    /// Cheap byte pre-filter run before JSON decoding. May admit false positives
    /// (e.g. a `response_item` whose head mentions "token_count") — `consume`
    /// still gates on the real `type` field.
    static func mightBeRelevant(_ line: Data) -> Bool {
        let head = line.count > relevanceHeadBytes ? line.prefix(relevanceHeadBytes) : line[...]
        return relevantMarkers.contains { head.range(of: $0) != nil }
    }

    /// The one line type that carries message content. Rejected from the head bytes,
    /// before any JSON parsing: `mightBeRelevant` can admit a `response_item` whose
    /// head happens to mention `token_count`, and deserializing such a line would
    /// materialize its content in memory — the token-count-only boundary is enforced
    /// here, not just on the decoded `type`. Rollout lines put the top-level `type`
    /// within the first ~100 bytes; a `payload.type` is never `response_item`.
    /// Matched against the head with ASCII whitespace removed, so a pretty-printed or
    /// space-after-colon rollout (`"type": "response_item"`) is still rejected. The CLI
    /// writes compact JSON today; this boundary is too important to depend on that.
    private static let responseItemMarker = Data("\"type\":\"response_item\"".utf8)
    private static let responseItemNameMarker = Data("\"response_item\"".utf8)

    static func isResponseItem(_ line: Data) -> Bool {
        let head = line.count > relevanceHeadBytes ? line.prefix(relevanceHeadBytes) : line[...]
        if head.range(of: responseItemMarker) != nil {
            return true
        }
        // Only pay for the copy when the cheap exact match missed but the name is present
        // anyway — i.e. something is sitting between the key and the value.
        guard head.range(of: responseItemNameMarker) != nil else { return false }
        var compacted = Data()
        compacted.reserveCapacity(head.count)
        var sawWhitespace = false
        for byte in head {
            switch byte {
            case 0x20, 0x09, 0x0A, 0x0D:
                sawWhitespace = true
            default:
                compacted.append(byte)
            }
        }
        guard sawWhitespace else { return false }
        return compacted.range(of: responseItemMarker) != nil
    }

    /// Feed one complete JSONL line (no trailing newline).
    /// - Returns: an entry for an attributable `token_count` line, else nil.
    mutating func consume(line: Data, lineIndex: Int) -> AssistantUsageEntry? {
        guard !Self.isResponseItem(line) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = object["type"] as? String else {
            corruptLineCount += 1
            return nil
        }

        switch type {
        case "session_meta":
            applySessionMeta(object["payload"] as? [String: Any])
            return nil
        case "turn_context":
            if let model = (object["payload"] as? [String: Any])?["model"] as? String, !model.isEmpty {
                currentModel = model
            }
            return nil
        case "event_msg":
            guard let payload = object["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count" else { return nil }
            return makeEntry(payload: payload, object: object, lineIndex: lineIndex)
        default:
            // response_item, world_state, compacted, … — never decoded further.
            return nil
        }
    }

    // MARK: - Private

    private mutating func applySessionMeta(_ payload: [String: Any]?) {
        guard let payload else { return }
        if let id = (payload["id"] as? String) ?? (payload["session_id"] as? String), !id.isEmpty {
            sessionId = id
        }
        if let dir = payload["cwd"] as? String, !dir.isEmpty {
            cwd = dir
        }
        if let git = payload["git"] as? [String: Any], let branch = git["branch"] as? String, !branch.isEmpty {
            gitBranch = branch
        }
    }

    private mutating func makeEntry(payload: [String: Any], object: [String: Any], lineIndex: Int) -> AssistantUsageEntry? {
        // `info` is null on rate-limit-only refreshes — nothing to count.
        guard let model = currentModel,
              let info = payload["info"] as? [String: Any],
              let last = info["last_token_usage"] as? [String: Any] else { return nil }

        // A rate-limit refresh re-emits the previous turn's `info` verbatim under a new
        // `ordinal`, so the reader's messageId dedup lets it through and the same
        // `last_token_usage` is counted twice. The cumulative total is the discriminator:
        // it only moves when a turn actually spent tokens.
        let total = TotalUsage(info["total_token_usage"])
        if let total {
            guard total != lastTotalUsage else { return nil }
        }

        // Either ISO 8601 shape (rollouts write fractional seconds; accept whole seconds
        // too). A missing / malformed timestamp is a corrupt line, never "now": during a
        // cold scan of old rollouts, `Date()` would drop a historical turn into the
        // current 5-hour / weekly windows and today's activity chart.
        guard let stamp = object["timestamp"] as? String, let timestamp = DateFormatters.parseISO8601(stamp) else {
            corruptLineCount += 1
            return nil
        }

        let input = Self.int(last["input_tokens"])
        let cached = Self.int(last["cached_input_tokens"])
        let cacheWrite = Self.int(last["cache_write_input_tokens"])
        let output = Self.int(last["output_tokens"])

        let resolvedSessionId = sessionId ?? fallbackSessionId
        let ordinal = (object["ordinal"] as? NSNumber)?.intValue ?? lineIndex

        // Recorded only for an entry we actually emit, so a corrupt-timestamp line
        // between two real turns can't make the next one look like a repeat.
        lastTotalUsage = total

        return AssistantUsageEntry(
            timestamp: timestamp,
            model: model,
            messageId: "\(resolvedSessionId):\(ordinal)",
            // Fresh (uncached, unwritten) input only — cached and cache-write tokens
            // are subsets of `input_tokens` and are reported in their own fields.
            inputTokens: max(0, input - cached - cacheWrite),
            outputTokens: output, // reasoning_output_tokens is a subset, already included
            cacheReadTokens: cached,
            cacheWriteTokens: cacheWrite,
            sessionId: resolvedSessionId,
            cwd: cwd,
            gitBranch: gitBranch,
            toolCallCount: 0 // would require decoding response_item lines — skipped for privacy
        )
    }

    /// JSONSerialization bridges numbers as NSNumber (Int or Double at runtime).
    private static func int(_ value: Any?) -> Int {
        (value as? NSNumber)?.intValue ?? 0
    }
}
