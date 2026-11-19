import Foundation
import Testing
@testable import AIBatteryCore

/// Pins the incremental-rebuild contract that the `cachedSeenIds` optimisation must
/// preserve: when several files change in the SAME dirty cycle, each file's previous
/// contribution is purged and its fresh entries added exactly once, with no
/// cross-file duplicates and no survivors from a removed message id.
@Suite("Reader incremental cache", .serialized)
struct ReaderIncrementalCacheTests {
    // MARK: - Claude reader

    private func makeProjectsDir() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("reader-incr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    private func assistantLine(messageId: String, sessionId: String, timestamp: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return """
        {"type":"assistant","timestamp":"\(formatter.string(from: timestamp))","sessionId":"\(sessionId)",\
        "message":{"role":"assistant","model":"claude-sonnet-4-5-20250929","id":"\(messageId)",\
        "usage":{"input_tokens":10,"output_tokens":5}}}
        """
    }

    @discardableResult
    private func writeClaude(_ lines: [String], project: String, session: String, root: URL) throws -> URL {
        let dir = root.appendingPathComponent(project)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(session).jsonl")
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
        return url
    }

    @Test func claudeReader_twoFilesChangedInOneCycle_mergesBothWithoutDuplicates() throws {
        let root = try makeProjectsDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let base = Date()

        let urlA = try writeClaude(
            [assistantLine(messageId: "a1", sessionId: "sa", timestamp: base)],
            project: "-proj-a", session: "ses-a", root: root
        )
        let urlB = try writeClaude(
            [assistantLine(messageId: "b1", sessionId: "sb", timestamp: base.addingTimeInterval(1))],
            project: "-proj-b", session: "ses-b", root: root
        )

        let reader = SessionLogReader(projectsURL: root)
        #expect(Set(reader.readAllUsageEntries().map(\.messageId)) == ["a1", "b1"])

        // Both files change in the SAME cycle: A appends, B replaces its only message id.
        try Data((
            [
                assistantLine(messageId: "a1", sessionId: "sa", timestamp: base),
                assistantLine(messageId: "a2", sessionId: "sa", timestamp: base.addingTimeInterval(2)),
            ].joined(separator: "\n") + "\n"
        ).utf8).write(to: urlA)
        try Data((assistantLine(messageId: "b2", sessionId: "sb", timestamp: base.addingTimeInterval(3)) + "\n").utf8)
            .write(to: urlB)
        let future = Date().addingTimeInterval(2)
        try FileManager.default.setAttributes([.modificationDate: future], ofItemAtPath: urlA.path)
        try FileManager.default.setAttributes([.modificationDate: future], ofItemAtPath: urlB.path)
        reader.invalidate()

        let entries = reader.readAllUsageEntries()
        #expect(Set(entries.map(\.messageId)) == ["a1", "a2", "b2"])
        #expect(entries.count == 3) // b1 purged, nothing duplicated
        #expect(entries.map(\.timestamp) == entries.map(\.timestamp).sorted())
    }

    @Test func claudeReader_deletedFileEntriesArePurgedAndCanReturn() throws {
        let root = try makeProjectsDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let base = Date()

        try writeClaude([assistantLine(messageId: "a1", sessionId: "sa", timestamp: base)],
                        project: "-proj-a", session: "ses-a", root: root)
        let urlB = try writeClaude([assistantLine(messageId: "b1", sessionId: "sb", timestamp: base.addingTimeInterval(1))],
                                   project: "-proj-b", session: "ses-b", root: root)

        let reader = SessionLogReader(projectsURL: root)
        #expect(reader.readAllUsageEntries().count == 2)

        try FileManager.default.removeItem(at: urlB)
        reader.invalidate()
        reader.expireDiscoveryTTLForTesting()
        #expect(Set(reader.readAllUsageEntries().map(\.messageId)) == ["a1"])

        // The same id coming back from a new file must be re-added, not swallowed by a stale set.
        try writeClaude([assistantLine(messageId: "b1", sessionId: "sb", timestamp: base.addingTimeInterval(1))],
                        project: "-proj-b", session: "ses-b2", root: root)
        reader.invalidate()
        reader.expireDiscoveryTTLForTesting()
        #expect(Set(reader.readAllUsageEntries().map(\.messageId)) == ["a1", "b1"])
    }

    // MARK: - Codex reader

    private func turnContext() -> String {
        #"{"timestamp":"2026-09-21T08:00:00.000Z","ordinal":1,"type":"turn_context","payload":{"model":"gpt-5.4"}}"#
    }

    private func tokenCount(ordinal: Int, timestamp: String) -> String {
        #"{"timestamp":"\#(timestamp)","ordinal":\#(ordinal),"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":10,"reasoning_output_tokens":0,"total_tokens":110}},"rate_limits":null}}"#
    }

    @discardableResult
    private func writeRollout(_ lines: [String], datePath: String, name: String, root: URL) throws -> URL {
        let dir = root.appendingPathComponent(datePath)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(name).jsonl")
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
        return url
    }

    @Test func codexReader_twoFilesChangedInOneCycle_mergesBothWithoutDuplicates() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-incr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let urlA = try writeRollout([turnContext(), tokenCount(ordinal: 5, timestamp: "2026-09-21T09:00:00.000Z")],
                                    datePath: "\(CodexTestDates.thisMonth)/21", name: "rollout-a", root: root)
        let urlB = try writeRollout([turnContext(), tokenCount(ordinal: 5, timestamp: "2026-09-21T09:30:00.000Z")],
                                    datePath: "\(CodexTestDates.thisMonth)/21", name: "rollout-b", root: root)

        let reader = CodexSessionLogReader(sessionsURL: root)
        #expect(reader.readAllUsageEntries().count == 2)
        let before = Set(reader.readAllUsageEntries().map(\.messageId))

        // Both files grow in the same cycle.
        try writeRollout([
            turnContext(),
            tokenCount(ordinal: 5, timestamp: "2026-09-21T09:00:00.000Z"),
            tokenCount(ordinal: 9, timestamp: "2026-09-21T09:10:00.000Z"),
        ], datePath: "\(CodexTestDates.thisMonth)/21", name: "rollout-a", root: root)
        try writeRollout([
            turnContext(),
            tokenCount(ordinal: 5, timestamp: "2026-09-21T09:30:00.000Z"),
            tokenCount(ordinal: 9, timestamp: "2026-09-21T09:40:00.000Z"),
        ], datePath: "\(CodexTestDates.thisMonth)/21", name: "rollout-b", root: root)
        let future = Date().addingTimeInterval(2)
        try FileManager.default.setAttributes([.modificationDate: future], ofItemAtPath: urlA.path)
        try FileManager.default.setAttributes([.modificationDate: future], ofItemAtPath: urlB.path)
        reader.invalidate()

        let entries = reader.readAllUsageEntries()
        #expect(entries.count == 4)
        #expect(Set(entries.map(\.messageId)).count == 4)
        #expect(before.isSubset(of: Set(entries.map(\.messageId))))
        #expect(entries.map(\.timestamp) == entries.map(\.timestamp).sorted())
    }
}
