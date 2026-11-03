import Foundation
import Testing
@testable import AIBatteryCore

/// Full-scale check against the developer's real `~/.codex/sessions` tree. Opt-in only
/// (`AIBATTERY_REAL_CODEX_LOGS=1`) — CI has no Codex logs and the suite must stay hermetic.
/// Reports timing + counts; asserts only shape invariants that hold for any real tree.
@Suite("CodexSessionLogReader — real data (opt-in)")
struct CodexSessionLogReaderRealDataTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AIBATTERY_REAL_CODEX_LOGS"] == "1"))
    func scansRealSessionsTreeQuicklyAndConsistently() throws {
        let root = CodexPaths.sessions
        try #require(FileManager.default.fileExists(atPath: root.path), "no ~/.codex/sessions on this machine")
        let reader = CodexSessionLogReader(sessionsURL: root)

        let coldStart = Date()
        let entries = reader.readAllUsageEntries()
        let cold = Date().timeIntervalSince(coldStart)

        let warmStart = Date()
        let again = reader.readAllUsageEntries()
        let warm = Date().timeIntervalSince(warmStart)

        reader.invalidate()
        let dirtyStart = Date()
        let rebuilt = reader.readAllUsageEntries()
        let dirty = Date().timeIntervalSince(dirtyStart)

        let models = Dictionary(grouping: entries, by: \.model).mapValues(\.count)
        print("REAL-DATA cold=\(String(format: "%.2f", cold))s warm=\(String(format: "%.4f", warm))s dirtyRebuild=\(String(format: "%.2f", dirty))s entries=\(entries.count) sessions=\(Set(entries.map(\.sessionId)).count) corrupt=\(reader.lastCorruptLineCount) models=\(models)")

        #expect(!entries.isEmpty)
        #expect(again.count == entries.count) // pure cache hit
        // Codex may be writing a rollout while this runs — a dirty rebuild can only grow.
        #expect(rebuilt.count >= entries.count)
        #expect(entries.map(\.timestamp) == entries.map(\.timestamp).sorted())
        #expect(Set(entries.map(\.messageId)).count == entries.count, "message ids must be unique across the tree")
        #expect(entries.allSatisfy { $0.model.hasPrefix("gpt-") })
        #expect(entries.allSatisfy { $0.inputTokens >= 0 && $0.outputTokens >= 0 })
        #expect(warm < 0.05, "warm read must be a cache hit")
        #expect(dirty < cold, "dirty rebuild should reuse fingerprints")
    }

    /// Appending one line to the **largest real rollout** must be far cheaper than a full
    /// re-read of it, and must produce exactly the same entries.
    ///
    /// This is the measurement the Claude-side tail parse was built on, now pointed at
    /// the file that is actually bigger: the active Codex rollout runs 20-25 MB against
    /// Claude's ~9 MB, and the CLI writes to it continuously. The copy is written to a
    /// temp tree so the real file is never touched.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AIBATTERY_REAL_CODEX_LOGS"] == "1"))
    func appendToTheLargestRealRolloutIsCheaperThanAFullReparse() throws {
        let root = CodexPaths.sessions
        try #require(FileManager.default.fileExists(atPath: root.path), "no ~/.codex/sessions on this machine")

        // Largest rollout on disk.
        var largest: (url: URL, size: Int)?
        if let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let url as URL in walker where url.pathExtension == "jsonl" {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                if size > (largest?.size ?? 0) {
                    largest = (url, size)
                }
            }
        }
        let source = try #require(largest, "no rollouts found")

        // Copy it into an isolated tree, keeping the date-directory shape the reader walks.
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("codex-tail-\(UUID().uuidString)")
        let dateDir = temp.appendingPathComponent("2026/01/01")
        try FileManager.default.createDirectory(at: dateDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let copy = dateDir.appendingPathComponent(source.url.lastPathComponent)
        try FileManager.default.copyItem(at: source.url, to: copy)
        // `copyItem` preserves the source's mtime, and the reader evicts cached entries
        // for files not modified today — which would refuse the resume and make this
        // measure two full parses. The file under test is the *active* rollout, so date
        // it accordingly.
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: copy.path)

        let reader = CodexSessionLogReader(sessionsURL: temp)
        let before = reader.readAllUsageEntries()
        try #require(!before.isEmpty, "largest rollout produced no entries")

        // Append one more terminated turn, exactly as the CLI would.
        let lastOrdinal = 9_000_000
        let appended = #"{"timestamp":"2026-01-01T00:00:00.000Z","ordinal":\#(lastOrdinal),"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":11,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":5,"reasoning_output_tokens":0,"total_tokens":16}},"rate_limits":null}}"# + "\n"
        let handle = try FileHandle(forWritingTo: copy)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(appended.utf8))
        try handle.close()

        reader.invalidate()
        let tailStart = Date()
        let incremental = reader.readAllUsageEntries()
        let tail = Date().timeIntervalSince(tailStart)

        let fullStart = Date()
        let fresh = CodexSessionLogReader(sessionsURL: temp).readAllUsageEntries()
        let full = Date().timeIntervalSince(fullStart)

        print("REAL-DATA-CODEX-TAILPARSE file=\(source.size / 1_048_576)MB entries=\(incremental.count) tail=\(String(format: "%.1f", tail * 1_000))ms full=\(String(format: "%.1f", full * 1_000))ms")

        // Same answer, not just a faster one.
        #expect(incremental.count == fresh.count)
        #expect(incremental.map(\.messageId) == fresh.map(\.messageId))
        var tailTokens = 0
        for entry in incremental {
            tailTokens += entry.inputTokens + entry.outputTokens + entry.cacheReadTokens + entry.cacheWriteTokens
        }
        var freshTokens = 0
        for entry in fresh {
            freshTokens += entry.inputTokens + entry.outputTokens + entry.cacheReadTokens + entry.cacheWriteTokens
        }
        #expect(tailTokens == freshTokens)
        #expect(incremental.count == before.count + 1)
        #expect(tail < full, "a tail parse must beat a full re-read of a \(source.size / 1_048_576)MB file")
    }
}
