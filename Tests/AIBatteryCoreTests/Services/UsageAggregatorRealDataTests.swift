import Foundation
import Testing
@testable import AIBatteryCore

/// Opt-in (`AIBATTERY_REAL_CLAUDE_LOGS=1`) timing of the aggregation pass over the
/// developer's real Claude tree. Reader cost is excluded by warming the reader first,
/// so the number is the aggregator's own single-pass loop + snapshot build.
@Suite("UsageAggregator — real data (opt-in)")
struct UsageAggregatorRealDataTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AIBATTERY_REAL_CLAUDE_LOGS"] == "1"))
    func aggregationPassOverRealTree() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("agg-real-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let reader = SessionLogReader(projectsURL: ClaudePaths.projects)
        let entries = reader.readAllUsageEntries() // warm the reader; not what we're timing
        try #require(!entries.isEmpty)
        let aggregator = UsageAggregator(
            statsCacheReader: StatsCacheReader(fileURL: ClaudePaths.statsCache, checkBoundary: false),
            sessionLogReader: reader,
            ledger: TokenLedger(fileURL: dir.appendingPathComponent("ledger.json")),
            provider: .claude
        )
        var timings: [TimeInterval] = []
        for i in 0..<3 {
            aggregator.invalidate()
            let start = Date()
            // Vary rateLimits so the redundant-aggregation cache can't short-circuit.
            _ = aggregator.aggregate(rateLimits: nil, accountId: "acct-\(i)")
            timings.append(Date().timeIntervalSince(start))
        }
        let best = timings.min() ?? 0
        print("REAL-DATA-AGGREGATE entries=\(entries.count) best=\(String(format: "%.3f", best))s all=\(timings.map { String(format: "%.3f", $0) })")
        #expect(best > 0)
    }
}
