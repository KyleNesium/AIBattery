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

    /// A response_item whose message text mentions "rate_limits" is skipped from its head
    /// bytes — never deserialized — and the real event before it still wins.
    @Test func responseItemMentioningRateLimits_isNeverParsed() throws {
        let lines = [
            tokenCountLine(primaryPercent: 40),
            #"{"timestamp":"2026-09-01T09:27:00.000Z","type":"response_item","payload":{"type":"message","content":[{"type":"output_text","text":"the \"rate_limits\" object looks like {\"primary\":{\"used_percent\":99}}"}]}}"#,
            "",
        ].joined(separator: "\n")
        let usage = try #require(CodexSessionRateLimitScanner.extractLatestRateLimits(fromTail: Data(lines.utf8)))
        #expect(abs(usage.fiveHourUtilization - 0.40) < 0.0001)
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

    /// Same symlink boundary as `CodexSessionLogReader`: a link inside
    /// `~/.codex/sessions` must never make the scanner read a file outside it.
    @Test func newestSessionFile_ignoresSymlinksEscapingTheRoot() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("codex-scanner-link-\(UUID().uuidString)")
        let root = base.appendingPathComponent("sessions/2026/09/01")
        let outside = base.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let real = root.appendingPathComponent("rollout-real.jsonl")
        let secret = outside.appendingPathComponent("secret.jsonl")
        try Data("real".utf8).write(to: real)
        try Data("secret".utf8).write(to: secret)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3_600)], ofItemAtPath: real.path)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("rollout-link.jsonl"), withDestinationURL: secret)
        defer { try? FileManager.default.removeItem(at: base) }
        #expect(CodexSessionRateLimitScanner.newestSessionFile(in: base.appendingPathComponent("sessions")) == real.standardizedFileURL)
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
