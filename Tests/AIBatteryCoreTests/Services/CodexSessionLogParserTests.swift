import Foundation
import Testing
@testable import AIBatteryCore

/// Fixture lines lifted from a real Codex CLI 0.152 rollout file (paths/ids redacted).
@Suite("CodexSessionLogParser")
struct CodexSessionLogParserTests {
    private let sessionMeta = #"{"timestamp":"2026-09-03T13:10:42.156Z","ordinal":0,"type":"session_meta","payload":{"session_id":"01a06764-9c28-78d1-9b78-00cf239db521","id":"01a06764-9c28-78d1-9b78-00cf239db521","timestamp":"2026-09-03T13:10:42.010Z","cwd":"/Users/me/work/proj","originator":"codex_exec","cli_version":"0.152.0","source":"exec","model_provider":"openai","git":{"branch":"feat/x","commit_hash":"abc"},"base_instructions":{"text":"You are Codex"}}}"#
    private let turnContext = #"{"timestamp":"2026-09-03T13:10:42.200Z","ordinal":2,"type":"turn_context","payload":{"cwd":"/Users/me/work/proj","model":"gpt-5.4","approval_policy":"never"}}"#
    private let turnContextSol = #"{"timestamp":"2026-09-03T13:20:00.000Z","ordinal":40,"type":"turn_context","payload":{"cwd":"/Users/me/work/proj","model":"gpt-5.6-sol"}}"#
    private let tokenCount = #"{"timestamp":"2026-09-03T13:10:58.838Z","ordinal":21,"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":53405,"cached_input_tokens":32640,"cache_write_input_tokens":0,"output_tokens":446,"reasoning_output_tokens":20,"total_tokens":53851},"last_token_usage":{"input_tokens":31894,"cached_input_tokens":21376,"cache_write_input_tokens":0,"output_tokens":233,"reasoning_output_tokens":20,"total_tokens":32127},"model_context_window":258400},"rate_limits":{"limit_id":"codex","primary":null,"secondary":null,"plan_type":"business"}}}"#
    private let tokenCountNullInfo = #"{"timestamp":"2026-09-03T13:11:00.000Z","ordinal":22,"type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"limit_id":"codex","primary":{"used_percent":19.0,"window_minutes":300,"resets_at":1781288517}}}}"#
    private let tokenCountCacheWrite = #"{"timestamp":"2026-09-03T13:12:00.000Z","ordinal":30,"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":80,"cache_write_input_tokens":30,"output_tokens":5,"reasoning_output_tokens":0,"total_tokens":105}},"rate_limits":null}}"#
    private let responseItem = #"{"timestamp":"2026-09-03T13:10:50.000Z","ordinal":10,"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"see below"},{"type":"token_count","text":"a content block whose type collides with the event name"}]}}"#

    private func line(_ s: String) -> Data {
        Data(s.utf8)
    }

    @Test func sessionMeta_setsIdentity() {
        var parser = CodexSessionLogParser(fallbackSessionId: "rollout-x")
        #expect(parser.consume(line: line(sessionMeta), lineIndex: 0) == nil)
        #expect(parser.sessionId == "01a06764-9c28-78d1-9b78-00cf239db521")
        #expect(parser.cwd == "/Users/me/work/proj")
        #expect(parser.gitBranch == "feat/x")
        #expect(parser.corruptLineCount == 0)
    }

    @Test func tokenCount_beforeTurnContext_isSkipped() {
        var parser = CodexSessionLogParser(fallbackSessionId: "rollout-x")
        _ = parser.consume(line: line(sessionMeta), lineIndex: 0)
        #expect(parser.consume(line: line(tokenCount), lineIndex: 1) == nil)
        #expect(parser.corruptLineCount == 0)
    }

    @Test func tokenCount_afterTurnContext_mapsFields() throws {
        var parser = CodexSessionLogParser(fallbackSessionId: "rollout-x")
        _ = parser.consume(line: line(sessionMeta), lineIndex: 0)
        _ = parser.consume(line: line(turnContext), lineIndex: 1)
        let entryResult = parser.consume(line: line(tokenCount), lineIndex: 2)
        let entry = try #require(entryResult)

        #expect(entry.model == "gpt-5.4")
        #expect(entry.inputTokens == 31_894 - 21_376) // fresh input only
        #expect(entry.cacheReadTokens == 21_376)
        #expect(entry.cacheWriteTokens == 0)
        #expect(entry.outputTokens == 233) // reasoning is a subset, already included
        #expect(entry.sessionId == "01a06764-9c28-78d1-9b78-00cf239db521")
        #expect(entry.messageId == "01a06764-9c28-78d1-9b78-00cf239db521:21") // ordinal, not line index
        #expect(entry.cwd == "/Users/me/work/proj")
        #expect(entry.gitBranch == "feat/x")
        #expect(entry.toolCallCount == 0)
        let expected = try #require(DateFormatters.iso8601.date(from: "2026-09-03T13:10:58.838Z"))
        #expect(abs(entry.timestamp.timeIntervalSince(expected)) < 0.001)
    }

    @Test func tokenCount_cacheWriteSubtractedAndClamped() throws {
        var parser = CodexSessionLogParser(fallbackSessionId: "rollout-x")
        _ = parser.consume(line: line(turnContext), lineIndex: 0)
        let entryResult = parser.consume(line: line(tokenCountCacheWrite), lineIndex: 1)
        let entry = try #require(entryResult)
        // 100 − 80 cached − 30 cache-write → clamped to 0, never negative
        #expect(entry.inputTokens == 0)
        #expect(entry.cacheReadTokens == 80)
        #expect(entry.cacheWriteTokens == 30)
    }

    @Test func tokenCount_nullInfo_isSkipped() {
        var parser = CodexSessionLogParser(fallbackSessionId: "rollout-x")
        _ = parser.consume(line: line(turnContext), lineIndex: 0)
        #expect(parser.consume(line: line(tokenCountNullInfo), lineIndex: 1) == nil)
        #expect(parser.corruptLineCount == 0)
    }

    @Test func responseItem_isNeverDecodedIntoAnEntry() {
        var parser = CodexSessionLogParser(fallbackSessionId: "rollout-x")
        _ = parser.consume(line: line(turnContext), lineIndex: 0)
        // A content block's type collides with "token_count" — the byte pre-filter passes it,
        // but the type check must reject it before anything in `payload` is read.
        #expect(CodexSessionLogParser.mightBeRelevant(line(responseItem)))
        #expect(parser.consume(line: line(responseItem), lineIndex: 1) == nil)
        #expect(parser.corruptLineCount == 0)
    }

    @Test func mightBeRelevant_rejectsUnrelatedLines() {
        #expect(!CodexSessionLogParser.mightBeRelevant(line(#"{"type":"event_msg","payload":{"type":"task_started"}}"#)))
        #expect(CodexSessionLogParser.mightBeRelevant(line(sessionMeta)))
        #expect(CodexSessionLogParser.mightBeRelevant(line(turnContext)))
        #expect(CodexSessionLogParser.mightBeRelevant(line(tokenCount)))
    }

    @Test func malformedJSON_countsCorrupt() {
        var parser = CodexSessionLogParser(fallbackSessionId: "rollout-x")
        #expect(parser.consume(line: line(#"{"type":"turn_context","payload":{"model":"#), lineIndex: 0) == nil)
        #expect(parser.corruptLineCount == 1)
    }

    @Test func missingSessionMeta_usesFallbackSessionId() throws {
        var parser = CodexSessionLogParser(fallbackSessionId: "rollout-2026-09-03T15-10-42-abc")
        _ = parser.consume(line: line(turnContext), lineIndex: 0)
        let entryResult = parser.consume(line: line(tokenCount), lineIndex: 1)
        let entry = try #require(entryResult)
        #expect(entry.sessionId == "rollout-2026-09-03T15-10-42-abc")
        #expect(entry.messageId == "rollout-2026-09-03T15-10-42-abc:21")
        #expect(entry.cwd == nil)
    }

    @Test func turnContext_switchesModelMidFile() throws {
        var parser = CodexSessionLogParser(fallbackSessionId: "rollout-x")
        _ = parser.consume(line: line(turnContext), lineIndex: 0)
        let firstResult = parser.consume(line: line(tokenCount), lineIndex: 1)
        let first = try #require(firstResult)
        _ = parser.consume(line: line(turnContextSol), lineIndex: 2)
        let secondResult = parser.consume(line: line(tokenCountCacheWrite), lineIndex: 3)
        let second = try #require(secondResult)
        #expect(first.model == "gpt-5.4")
        #expect(second.model == "gpt-5.6-sol")
    }
}
