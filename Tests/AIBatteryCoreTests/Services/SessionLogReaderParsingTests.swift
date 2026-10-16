import Testing
import Foundation
@testable import AIBatteryCore

/// Line-level parsing behaviour of `SessionLogReader.readSessionFile` that only shows
/// up when several JSONL lines interact: per-message tool-call coalescing, oversized
/// line skipping, and timestamp validation.
@Suite("SessionLogReader — line parsing")
struct SessionLogReaderParsingTests {
    // MARK: - Helpers

    private func makeProjectsDir() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("slr-parsing-\(UUID().uuidString)")
        let projectDir = tmp.appendingPathComponent("projects").appendingPathComponent("-test-project")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        return tmp.appendingPathComponent("projects")
    }

    private func write(_ lines: [String], to projectsDir: URL, name: String = "session.jsonl") throws {
        let url = projectsDir.appendingPathComponent("-test-project").appendingPathComponent(name)
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
    }

    /// One assistant line. `toolUses` tool_use blocks (plus one text block) share `messageId`.
    private func line(
        messageId: String,
        toolUses: Int,
        timestamp: String? = "2026-02-17T10:00:00.000Z",
        input: Int = 100
    ) -> String {
        var blocks = [#"{"type":"text","text":"x"}"#]
        blocks += (0..<toolUses).map { #"{"type":"tool_use","id":"tu-\#($0)","name":"Read","input":{}}"# }
        let ts = timestamp.map { #""timestamp":"\#($0)","# } ?? ""
        return #"{"type":"assistant",\#(ts)"sessionId":"ses-1","message":{"role":"assistant","model":"claude-sonnet-4-5-20250929","id":"\#(messageId)","content":[\#(blocks.joined(separator: ","))],"usage":{"input_tokens":\#(input),"output_tokens":50}}}"#
    }

    // MARK: - A1: tool_use coalescing across lines sharing a message id

    @Test func toolCalls_textLineThenToolUseLine_sameId_countsOne() throws {
        let dir = try makeProjectsDir()
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        // Claude Code writes one line per content block with the same message.id;
        // the first is usually text/thinking and carries zero tool_use blocks.
        try write([line(messageId: "msg-1", toolUses: 0), line(messageId: "msg-1", toolUses: 1)], to: dir)

        let entries = SessionLogReader(projectsURL: dir).readAllUsageEntries()

        #expect(entries.count == 1)
        #expect(entries.first?.toolCallCount == 1)
    }

    @Test func toolCalls_threeLinesSameId_sumsToolUseBlocks() throws {
        let dir = try makeProjectsDir()
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        try write([
            line(messageId: "msg-1", toolUses: 2),
            line(messageId: "msg-1", toolUses: 1),
            line(messageId: "msg-1", toolUses: 0),
        ], to: dir)

        let entries = SessionLogReader(projectsURL: dir).readAllUsageEntries()

        #expect(entries.count == 1)
        #expect(entries.first?.toolCallCount == 3)
        // Token usage is identical on every line of a message — counted once, not summed.
        #expect(entries.first?.inputTokens == 100)
    }

    @Test func toolCalls_distinctIds_stayPerMessage() throws {
        let dir = try makeProjectsDir()
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        try write([line(messageId: "msg-1", toolUses: 2), line(messageId: "msg-2", toolUses: 1)], to: dir)

        let entries = SessionLogReader(projectsURL: dir).readAllUsageEntries()

        #expect(entries.map(\.toolCallCount).sorted() == [1, 2])
    }
}
