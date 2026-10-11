import Foundation
import Testing
@testable import AIBatteryCore

@Suite("CodexSessionLogReader", .serialized)
struct CodexSessionLogReaderTests {
    // MARK: - Fixtures

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-reader-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func turnContext(model: String = "gpt-5.4") -> String {
        #"{"timestamp":"2026-09-21T08:00:00.000Z","ordinal":1,"type":"turn_context","payload":{"model":"\#(model)"}}"#
    }

    private func tokenCount(ordinal: Int, timestamp: String, input: Int = 100, output: Int = 10) -> String {
        #"{"timestamp":"\#(timestamp)","ordinal":\#(ordinal),"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":\#(input),"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":\#(output),"reasoning_output_tokens":0,"total_tokens":\#(input + output)}},"rate_limits":null}}"#
    }

    /// Writes `lines` to `<root>/<datePath>/<name>.jsonl`, creating the nested date dirs.
    @discardableResult
    private func writeRollout(_ lines: [String], datePath: String, name: String, root: URL, trailingNewline: Bool = true) throws -> URL {
        let dir = root.appendingPathComponent(datePath)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(name).jsonl")
        let content = lines.joined(separator: "\n") + (trailingNewline ? "\n" : "")
        try Data(content.utf8).write(to: url)
        return url
    }

    // MARK: - Tests

    @Test func readsEntriesAcrossNestedDateDirs_sortedAscending() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeRollout([turnContext(), tokenCount(ordinal: 5, timestamp: "2026-09-20T10:00:00.000Z")],
                         datePath: "2026/09/20", name: "rollout-a", root: root)
        try writeRollout([
            turnContext(),
            tokenCount(ordinal: 5, timestamp: "2026-09-21T09:00:00.000Z"),
            tokenCount(ordinal: 9, timestamp: "2026-09-21T09:05:00.000Z"),
        ],
        datePath: "2026/09/21", name: "rollout-b", root: root)

        let reader = CodexSessionLogReader(sessionsURL: root)
        let entries = reader.readAllUsageEntries()

        #expect(entries.count == 3)
        #expect(entries.map(\.timestamp) == entries.map(\.timestamp).sorted())
        #expect(entries.allSatisfy { $0.model == "gpt-5.4" })
        // No session_meta → file stem is the session id, so IDs never collide across files.
        #expect(Set(entries.map(\.messageId)).count == 3)
        #expect(entries.first?.sessionId == "rollout-a")
    }

    @Test func unchangedFile_isServedFromCache_changedFile_isReparsed() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try writeRollout([turnContext(), tokenCount(ordinal: 5, timestamp: "2026-09-21T09:00:00.000Z")],
                                   datePath: "2026/09/21", name: "rollout-a", root: root)
        let reader = CodexSessionLogReader(sessionsURL: root)

        #expect(reader.readAllUsageEntries().count == 1)
        #expect(reader.readAllUsageEntries().count == 1) // cache hit, same result

        // Append a turn and bump the fingerprint (size changes; force a distinct modDate too).
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((tokenCount(ordinal: 9, timestamp: "2026-09-21T09:05:00.000Z") + "\n").utf8))
        try handle.close()
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 5)], ofItemAtPath: url.path)
        reader.invalidate()

        #expect(reader.readAllUsageEntries().count == 2)
    }

    @Test func deletedFile_entriesAreRemoved() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeRollout([turnContext(), tokenCount(ordinal: 5, timestamp: "2026-09-21T09:00:00.000Z")],
                         datePath: "2026/09/21", name: "rollout-a", root: root)
        let gone = try writeRollout([turnContext(), tokenCount(ordinal: 5, timestamp: "2026-09-21T10:00:00.000Z")],
                                    datePath: "2026/09/21", name: "rollout-b", root: root)
        let reader = CodexSessionLogReader(sessionsURL: root)
        #expect(reader.readAllUsageEntries().count == 2)

        try FileManager.default.removeItem(at: gone)
        reader.invalidate()

        let remaining = reader.readAllUsageEntries()
        #expect(remaining.count == 1)
        #expect(remaining.first?.sessionId == "rollout-a")
    }

    @Test func evictsRawEntriesForFilesNotModifiedToday() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let old = try writeRollout([turnContext(), tokenCount(ordinal: 5, timestamp: "2026-09-20T09:00:00.000Z")],
                                   datePath: "2026/09/20", name: "rollout-old", root: root)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -2 * 86_400)], ofItemAtPath: old.path)
        try writeRollout([turnContext(), tokenCount(ordinal: 5, timestamp: "2026-09-21T09:00:00.000Z")],
                         datePath: "2026/09/21", name: "rollout-today", root: root)

        let reader = CodexSessionLogReader(sessionsURL: root)
        #expect(reader.readAllUsageEntries().count == 2)
        // Yesterday's file keeps only its fingerprint; today's keeps live entries.
        #expect(reader.cacheEntriesWithLiveEntriesCountForTesting() == 1)
        // Evicted entries still come back from the merged cache on the next read.
        #expect(reader.readAllUsageEntries().count == 2)
    }

    @Test func skipsTrailingPartialLine() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let partial = String(tokenCount(ordinal: 9, timestamp: "2026-09-21T09:05:00.000Z").dropLast(20))
        try writeRollout([turnContext(), tokenCount(ordinal: 5, timestamp: "2026-09-21T09:00:00.000Z"), partial],
                         datePath: "2026/09/21", name: "rollout-a", root: root, trailingNewline: false)

        let reader = CodexSessionLogReader(sessionsURL: root)
        #expect(reader.readAllUsageEntries().count == 1)
        #expect(reader.lastCorruptLineCount == 0) // a partial tail is "still being written", not corrupt
    }

    @Test func symlinkOutsideRoot_isIgnored() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("codex-outside-\(UUID().uuidString).jsonl")
        try Data((turnContext() + "\n" + tokenCount(ordinal: 5, timestamp: "2026-09-21T09:00:00.000Z") + "\n").utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        let dir = root.appendingPathComponent("2026/09/21")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("rollout-link.jsonl"), withDestinationURL: outside)

        let reader = CodexSessionLogReader(sessionsURL: root)
        #expect(reader.readAllUsageEntries().isEmpty)
    }

    @Test func missingRoot_returnsEmpty() {
        let reader = CodexSessionLogReader(sessionsURL: FileManager.default.temporaryDirectory.appendingPathComponent("does-not-exist-\(UUID().uuidString)"))
        #expect(reader.readAllUsageEntries().isEmpty)
        #expect(reader.lastCorruptLineCount == 0)
    }

    @Test func corruptLine_isCountedAndSkipped() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeRollout([
            turnContext(),
            #"{"type":"turn_context","payload":{"model":"#,
            tokenCount(ordinal: 5, timestamp: "2026-09-21T09:00:00.000Z"),
        ],
        datePath: "2026/09/21", name: "rollout-a", root: root)
        let reader = CodexSessionLogReader(sessionsURL: root)
        #expect(reader.readAllUsageEntries().count == 1)
        #expect(reader.lastCorruptLineCount == 1)
    }
}
