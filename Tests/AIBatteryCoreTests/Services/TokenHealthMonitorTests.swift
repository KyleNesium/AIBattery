import Testing
import Foundation
@testable import AIBatteryCore

@Suite("TokenHealthMonitor")
struct TokenHealthMonitorTests {

    let monitor = TokenHealthMonitor()

    // MARK: - Band classification

    @Test func assess_greenBand() {
        // Low usage → green
        let entries = [makeEntry(sessionId: "s1", input: 10_000, output: 500)]
        let result = monitor.assessCurrentSession(entries: entries)
        #expect(result != nil)
        #expect(result?.band == .green)
    }

    @Test func assess_orangeBand() {
        // 60%+ of usable window (160K) → orange
        // Need totalUsed > 96K. Input=95K + output across entries
        let entries = [
            makeEntry(sessionId: "s1", input: 90_000, output: 3_000),
            makeEntry(sessionId: "s1", input: 95_000, output: 3_000),
        ]
        let result = monitor.assessCurrentSession(entries: entries)
        #expect(result != nil)
        // totalUsed = input(95K) + cacheRead(0) + cacheWrite(0) + sumOutput(6K) = 101K
        // percentage = 101K / 160K * 100 = 63.1% → orange
        #expect(result?.band == .orange)
    }

    @Test func assess_redBand() {
        // 80%+ of usable window → red
        // Need totalUsed > 128K
        let entries = [
            makeEntry(sessionId: "s1", input: 120_000, output: 5_000),
            makeEntry(sessionId: "s1", input: 125_000, output: 5_000),
        ]
        let result = monitor.assessCurrentSession(entries: entries)
        #expect(result != nil)
        // totalUsed = 125K + 10K output = 135K
        // percentage = 135K / 160K * 100 = 84.4% → red
        #expect(result?.band == .red)
    }

    // MARK: - Empty entries

    @Test func assess_emptyEntries() {
        let result = monitor.assessCurrentSession(entries: [])
        #expect(result == nil)
    }

    // MARK: - Overflow guards

    @Test func assess_overflowCapsAtContextWindow() {
        // Absurdly large input — should be capped
        let entries = [makeEntry(sessionId: "s1", input: 999_999_999, output: 999_999_999)]
        let result = monitor.assessCurrentSession(entries: entries)
        #expect(result != nil)
        #expect(result!.totalUsed <= result!.contextWindow)
    }

    // MARK: - Turn count warnings

    @Test func assess_mildTurnWarning() {
        // 16 turns → mild warning (> 15, ≤ 25)
        let entries = (0..<16).map { i in
            makeEntry(sessionId: "s1", input: 1000 * (i + 1), output: 100, timestamp: Date().addingTimeInterval(Double(i) * 60))
        }
        let result = monitor.assessCurrentSession(entries: entries)
        #expect(result != nil)
        #expect(result?.turnCount == 16)
        let turnWarnings = result!.warnings.filter { $0.message.contains("turns") }
        #expect(turnWarnings.count == 1)
        #expect(turnWarnings.first?.severity == .mild)
    }

    @Test func assess_strongTurnWarning() {
        // 26 turns → strong warning (> 25)
        let entries = (0..<26).map { i in
            makeEntry(sessionId: "s1", input: 500 * (i + 1), output: 50, timestamp: Date().addingTimeInterval(Double(i) * 60))
        }
        let result = monitor.assessCurrentSession(entries: entries)
        #expect(result != nil)
        let turnWarnings = result!.warnings.filter { $0.message.contains("turns") }
        #expect(turnWarnings.count == 1)
        #expect(turnWarnings.first?.severity == .strong)
    }

    @Test func assess_noTurnWarning() {
        // 10 turns → no warning (≤ 15)
        let entries = (0..<10).map { i in
            makeEntry(sessionId: "s1", input: 500, output: 50, timestamp: Date().addingTimeInterval(Double(i) * 60))
        }
        let result = monitor.assessCurrentSession(entries: entries)
        #expect(result != nil)
        let turnWarnings = result!.warnings.filter { $0.message.contains("turns") }
        #expect(turnWarnings.isEmpty)
    }

    // MARK: - Input/output ratio warning

    @Test func assess_highRatioWarning() {
        // Input:output ratio > 20:1
        let entries = [makeEntry(sessionId: "s1", input: 50_000, output: 100)]
        let result = monitor.assessCurrentSession(entries: entries)
        #expect(result != nil)
        let ratioWarnings = result!.warnings.filter { $0.message.contains("ratio") }
        #expect(ratioWarnings.count == 1)
    }

    @Test func assess_normalRatio_noWarning() {
        let entries = [makeEntry(sessionId: "s1", input: 5_000, output: 2_000)]
        let result = monitor.assessCurrentSession(entries: entries)
        #expect(result != nil)
        let ratioWarnings = result!.warnings.filter { $0.message.contains("ratio") }
        #expect(ratioWarnings.isEmpty)
    }

    // MARK: - Multiple sessions (assessAllSessions)

    @Test func assessAllSessions_groupsBySessionId() {
        let entries = [
            makeEntry(sessionId: "s1", input: 1000, output: 100),
            makeEntry(sessionId: "s2", input: 2000, output: 200),
            makeEntry(sessionId: "s1", input: 1500, output: 150),
        ]
        let results = monitor.assessAllSessions(entries: entries)
        #expect(results.count == 2)
        #expect(results["s1"] != nil)
        #expect(results["s2"] != nil)
        #expect(results["s1"]?.turnCount == 2)
        #expect(results["s2"]?.turnCount == 1)
    }

    // MARK: - topSessions filtering/sorting

    @Test func topSessions_excludesOldSessions() {
        let recentTime = Date()
        let oldTime = Date().addingTimeInterval(-48 * 3600) // 48h ago

        let entries = [
            makeEntry(sessionId: "recent", input: 1000, output: 100, timestamp: recentTime),
            makeEntry(sessionId: "old", input: 2000, output: 200, timestamp: oldTime),
        ]
        let top = monitor.topSessions(entries: entries, limit: 5)
        // Only recent session should be included (24h cutoff)
        #expect(top.count == 1)
        #expect(top.first?.id == "recent")
    }

    @Test func topSessions_sortedByRecency() {
        let now = Date()
        let entries = [
            makeEntry(sessionId: "s1", input: 1000, output: 100, timestamp: now.addingTimeInterval(-3600)),
            makeEntry(sessionId: "s2", input: 2000, output: 200, timestamp: now),
            makeEntry(sessionId: "s3", input: 3000, output: 300, timestamp: now.addingTimeInterval(-7200)),
        ]
        let top = monitor.topSessions(entries: entries, limit: 5)
        #expect(top.count == 3)
        #expect(top[0].id == "s2")
        #expect(top[1].id == "s1")
        #expect(top[2].id == "s3")
    }

    @Test func topSessions_respectsLimit() {
        let now = Date()
        let entries = (0..<10).map { i in
            makeEntry(sessionId: "s\(i)", input: 1000, output: 100, timestamp: now.addingTimeInterval(Double(-i) * 60))
        }
        let top = monitor.topSessions(entries: entries, limit: 3)
        #expect(top.count == 3)
    }

    // MARK: - Metadata extraction

    @Test func assess_extractsProjectName() {
        let entries = [makeEntry(sessionId: "s1", input: 1000, output: 100, cwd: "/Users/test/MyProject")]
        let result = monitor.assessCurrentSession(entries: entries)
        #expect(result?.projectName == "MyProject")
    }

    @Test func assess_extractsGitBranch() {
        let entries = [makeEntry(sessionId: "s1", input: 1000, output: 100, cwd: "/Users/test/MyProject", gitBranch: "feat/tests")]
        let result = monitor.assessCurrentSession(entries: entries)
        #expect(result?.gitBranch == "feat/tests")
    }

    // MARK: - Velocity calculation

    @Test func assess_velocityCalculated() {
        let start = Date()
        let entries = [
            makeEntry(sessionId: "s1", input: 5_000, output: 500, timestamp: start),
            makeEntry(sessionId: "s1", input: 10_000, output: 500, timestamp: start.addingTimeInterval(120)), // 2 min later
        ]
        let result = monitor.assessCurrentSession(entries: entries)
        #expect(result?.tokensPerMinute != nil)
        // totalUsed = 10K + 1K output = 11K, duration = 2 min → ~5500/min
        #expect(result!.tokensPerMinute! > 0)
    }

    @Test func assess_noVelocity_singleEntry() {
        let entries = [makeEntry(sessionId: "s1", input: 5_000, output: 500)]
        let result = monitor.assessCurrentSession(entries: entries)
        #expect(result?.tokensPerMinute == nil)
    }

    @Test func assess_noVelocity_tooShort() {
        let start = Date()
        let entries = [
            makeEntry(sessionId: "s1", input: 5_000, output: 500, timestamp: start),
            makeEntry(sessionId: "s1", input: 6_000, output: 500, timestamp: start.addingTimeInterval(30)), // 30s
        ]
        let result = monitor.assessCurrentSession(entries: entries)
        // Duration < 60s → no velocity
        #expect(result?.tokensPerMinute == nil)
    }

    // MARK: - Custom config thresholds

    @Test func assess_customThresholds() {
        var config = TokenHealthConfig()
        config.greenThreshold = 30.0
        config.redThreshold = 50.0
        let customMonitor = TokenHealthMonitor(config: config)

        // 40% usage → with default would be green, with custom thresholds → orange
        // usable window = 160K. 40% = 64K.
        let entries = [makeEntry(sessionId: "s1", input: 60_000, output: 4_000)]
        let result = customMonitor.assessCurrentSession(entries: entries)
        #expect(result?.band == .orange)
    }

    // MARK: - Helper

    private func makeEntry(
        sessionId: String,
        input: Int,
        output: Int,
        cacheRead: Int = 0,
        cacheWrite: Int = 0,
        timestamp: Date = Date(),
        model: String = "claude-opus-4-6",
        cwd: String? = nil,
        gitBranch: String? = nil
    ) -> AssistantUsageEntry {
        AssistantUsageEntry(
            timestamp: timestamp,
            model: model,
            messageId: UUID().uuidString,
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: cacheRead,
            cacheWriteTokens: cacheWrite,
            sessionId: sessionId,
            cwd: cwd,
            gitBranch: gitBranch
        )
    }
}
