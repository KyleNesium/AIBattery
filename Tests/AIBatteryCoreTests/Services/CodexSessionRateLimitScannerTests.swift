import Foundation
import Testing
@testable import AIBatteryCore

@Suite("CodexSessionRateLimitScanner")
struct CodexSessionRateLimitScannerTests {
    private func tokenCountLine(primaryPercent: Double) -> String {
        """
        {"timestamp":"2026-09-01T09:26:07.000Z","type":"event_msg","payload":{"type":"token_count",\
        "info":{"total_token_usage":{"input_tokens":1,"cached_input_tokens":0,"cache_write_input_tokens":0,\
        "output_tokens":1,"reasoning_output_tokens":0,"total_tokens":2}},\
        "rate_limits":{"limit_id":"codex","primary":{"used_percent":\(primaryPercent),"window_minutes":300,"resets_at":1788267090},\
        "secondary":{"used_percent":3.0,"window_minutes":10080,"resets_at":1788853890}}}}
        """
    }

    @Test func picksLastRateLimitsEvent() throws {
        let lines = [
            #"{"type":"session_meta","payload":{"id":"s1"}}"#,
            tokenCountLine(primaryPercent: 10),
            #"{"type":"response_item","payload":{}}"#,
            tokenCountLine(primaryPercent: 55),
            "", // trailing newline
        ].joined(separator: "\n")
        let usage = try #require(CodexSessionRateLimitScanner.extractLatestRateLimits(fromTail: Data(lines.utf8)))
        #expect(abs(usage.fiveHourUtilization - 0.55) < 0.0001) // the LAST event wins
    }

    @Test func skipsTruncatedTrailingLine() throws {
        // Tail reads can slice mid-line; a partial trailing line must be ignored.
        let lines = tokenCountLine(primaryPercent: 42) + "\n" +
            #"{"type":"event_msg","payload":{"type":"token_count","rate_li"#
        let usage = try #require(CodexSessionRateLimitScanner.extractLatestRateLimits(fromTail: Data(lines.utf8)))
        #expect(abs(usage.fiveHourUtilization - 0.42) < 0.0001)
    }

    @Test func noRateLimitsReturnsNil() {
        let lines = #"{"type":"session_meta","payload":{}}"# + "\n" + #"{"type":"response_item","payload":{}}"#
        #expect(CodexSessionRateLimitScanner.extractLatestRateLimits(fromTail: Data(lines.utf8)) == nil)
    }

    @Test func newestSessionFileWins() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("codex-scanner-\(UUID().uuidString)/2026/09/01")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let old = dir.appendingPathComponent("rollout-old.jsonl")
        let new = dir.appendingPathComponent("rollout-new.jsonl")
        try Data("old".utf8).write(to: old)
        try Data("new".utf8).write(to: new)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3_600)], ofItemAtPath: old.path)
        let root = dir.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        #expect(CodexSessionRateLimitScanner.newestSessionFile(in: root) == new)
        try? FileManager.default.removeItem(at: root)
    }

    @Test func survivesMultiByteCharacterAtTailBoundary() throws {
        // Tail seek can land mid-multi-byte character. Byte-level split + per-line
        // decode should survive this: partial first line fails to decode, but the
        // scan continues to find the valid rate_limits line.
        var data = Data([0x9F, 0x98, 0x80]) // trailing bytes of 😀 emoji
        data.append(UInt8(ascii: "\n"))
        let lineStr = tokenCountLine(primaryPercent: 77)
        let lineData = try #require(lineStr.data(using: .utf8))
        data.append(lineData)
        let usage = try #require(CodexSessionRateLimitScanner.extractLatestRateLimits(fromTail: data))
        #expect(abs(usage.fiveHourUtilization - 0.77) < 0.0001)
    }
}
