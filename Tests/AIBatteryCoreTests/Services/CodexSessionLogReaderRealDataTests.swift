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
}
