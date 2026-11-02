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

    /// Two independent aggregators over the same entries must produce the **same
    /// snapshot**, field for field.
    ///
    /// This is the real test of the tie-breaks: peak hour, the session-health ordering
    /// and the project rows all come out of unordered dictionaries, and `sort` is not
    /// stable, so before they broke ties explicitly the popover reordered itself between
    /// polls with no change in the data behind it. Timing three passes never caught that
    /// — nothing compared them. Separate instances (rather than one invalidated twice)
    /// because each has its own redundant-aggregation cache, so both genuinely compute;
    /// `UsageSnapshot ==` deliberately ignores `lastUpdated`, which is the only field
    /// that legitimately differs. 17k real entries across 2,240 sessions is far more
    /// tie-prone input than any fixture.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AIBATTERY_REAL_CLAUDE_LOGS"] == "1"))
    func twoAggregationPassesOverTheRealTreeAgreeExactly() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("agg-det-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // One warmed reader, shared: both passes must see byte-identical input, and the
        // real tree is being written to while this runs.
        let reader = SessionLogReader(projectsURL: ClaudePaths.projects)
        let entries = reader.readAllUsageEntries()
        try #require(!entries.isEmpty)

        func pass(_ name: String) -> UsageAggregator.AggregateResult {
            UsageAggregator(
                statsCacheReader: StatsCacheReader(fileURL: ClaudePaths.statsCache, checkBoundary: false),
                sessionLogReader: reader,
                ledger: TokenLedger(fileURL: dir.appendingPathComponent("\(name).json")),
                provider: .claude
            ).aggregate(rateLimits: nil, accountId: "acct-determinism")
        }

        let first = pass("first").detail
        let second = pass("second").detail
        let firstWide = pass("firstWide").providerWide
        let secondWide = pass("secondWide").providerWide

        #expect(first == second, "two detail passes over identical entries disagreed")
        #expect(firstWide == secondWide, "two provider-wide passes over identical entries disagreed")
        // Named separately: `==` is one boolean, and these are the fields whose order
        // used to drift, so a regression says which one rather than just "not equal".
        #expect(first.peakHour == second.peakHour)
        #expect(first.peakHourCount == second.peakHourCount)
        #expect(first.topSessionHealths.map(\.id) == second.topSessionHealths.map(\.id))
        #expect(first.projectTokens.map(\.id) == second.projectTokens.map(\.id))
        #expect(first.dailyActivity.map(\.date) == second.dailyActivity.map(\.date))
        #expect(first.modelTokens.map(\.id) == second.modelTokens.map(\.id))
        print("REAL-DATA-DETERMINISM entries=\(entries.count) sessions=\(first.topSessionHealths.count) projects=\(first.projectTokens.count) peakHour=\(String(describing: first.peakHour))")
    }
}
