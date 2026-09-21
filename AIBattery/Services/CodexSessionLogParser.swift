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
    /// Used for `sessionId` when the file has no `session_meta` line (the file
    /// name stem — stable across re-parses so message IDs stay deterministic).
    let fallbackSessionId: String

    init(fallbackSessionId: String) {
        self.fallbackSessionId = fallbackSessionId
    }

    private static let relevantMarkers: [Data] = [
        "\"session_meta\"", "\"turn_context\"", "\"token_count\"",
    ].compactMap { $0.data(using: .utf8) }

    /// Cheap byte pre-filter run before JSON decoding. May admit false positives
    /// (e.g. a `response_item` whose text mentions "token_count") — `consume`
    /// still gates on the real `type` field.
    static func mightBeRelevant(_ line: Data) -> Bool {
        relevantMarkers.contains { line.range(of: $0) != nil }
    }

    /// Feed one complete JSONL line (no trailing newline).
    /// - Returns: an entry for an attributable `token_count` line, else nil.
    mutating func consume(line: Data, lineIndex: Int) -> AssistantUsageEntry? {
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

    private func makeEntry(payload: [String: Any], object: [String: Any], lineIndex: Int) -> AssistantUsageEntry? {
        // `info` is null on rate-limit-only refreshes — nothing to count.
        guard let model = currentModel,
              let info = payload["info"] as? [String: Any],
              let last = info["last_token_usage"] as? [String: Any] else { return nil }

        let input = Self.int(last["input_tokens"])
        let cached = Self.int(last["cached_input_tokens"])
        let cacheWrite = Self.int(last["cache_write_input_tokens"])
        let output = Self.int(last["output_tokens"])

        let resolvedSessionId = sessionId ?? fallbackSessionId
        let ordinal = (object["ordinal"] as? NSNumber)?.intValue ?? lineIndex
        let timestamp = (object["timestamp"] as? String).flatMap { DateFormatters.iso8601.date(from: $0) } ?? Date()

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
