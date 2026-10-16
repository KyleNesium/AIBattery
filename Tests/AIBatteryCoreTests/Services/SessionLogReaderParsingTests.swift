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

    // MARK: - A15: oversized line is skipped once, to its newline

    @Test func oversizedLine_countedOnce_tailNotParsed_nextLineParsed() throws {
        let dir = try makeProjectsDir()
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        // 1.5 MB line whose last bytes are a *valid* assistant line ("ghost"): if the
        // reader only dropped the first 1 MB and kept streaming, the ghost would be
        // parsed as its own entry and the line would be counted once per MB.
        let ghost = line(messageId: "ghost", toolUses: 0)
        let pad = String(repeating: "x", count: 1_500_000 - ghost.utf8.count)
        try write([#"{"pad":""# + pad + #""}"# + ghost, line(messageId: "real", toolUses: 0)], to: dir)

        let reader = SessionLogReader(projectsURL: dir)
        let entries = reader.readAllUsageEntries()

        #expect(entries.map(\.messageId) == ["real"])
        #expect(reader.lastCorruptLineCount == 1)
    }

    @Test func oversizedLine_withoutTrailingNewline_isNotParsedAsTail() throws {
        let dir = try makeProjectsDir()
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let ghost = line(messageId: "ghost", toolUses: 0)
        let pad = String(repeating: "x", count: 1_500_000 - ghost.utf8.count)
        let url = dir.appendingPathComponent("-test-project").appendingPathComponent("session.jsonl")
        try Data((line(messageId: "real", toolUses: 0) + "\n" + #"{"pad":""# + pad + #""}"# + ghost).utf8).write(to: url)

        let reader = SessionLogReader(projectsURL: dir)
        let entries = reader.readAllUsageEntries()

        #expect(entries.map(\.messageId) == ["real"])
        #expect(reader.lastCorruptLineCount == 1)
    }

    @Test func toolCalls_distinctIds_stayPerMessage() throws {
        let dir = try makeProjectsDir()
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        try write([line(messageId: "msg-1", toolUses: 2), line(messageId: "msg-2", toolUses: 1)], to: dir)

        let entries = SessionLogReader(projectsURL: dir).readAllUsageEntries()

        #expect(entries.map(\.toolCallCount).sorted() == [1, 2])
    }
}
