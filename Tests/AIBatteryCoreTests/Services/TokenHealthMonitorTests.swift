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
        // 60%+ of usable window (1M) → orange
        // Need totalUsed > 600K
        let entries = [
            makeEntry(sessionId: "s1", input: 580_000, output: 30_000),
            makeEntry(sessionId: "s1", input: 595_000, output: 15_000),
        ]
        let result = monitor.assessCurrentSession(entries: entries)
        #expect(result != nil)
        // totalUsed = input(595K) + latestOutput(15K) = 610K
        // percentage = 610K / 1M * 100 = 61% → orange
        #expect(result?.band == .orange)
    }

    @Test func assess_redBand() {
        // 80%+ of usable window → red
        // Need totalUsed > 800K
        let entries = [
            makeEntry(sessionId: "s1", input: 780_000, output: 15_000),
            makeEntry(sessionId: "s1", input: 790_000, output: 15_000),
        ]
        let result = monitor.assessCurrentSession(entries: entries)
        #expect(result != nil)
        // totalUsed = 790K + 15K latestOutput = 805K
        // percentage = 805K / 1M * 100 = 80.5% → red
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

    @Test func assess_infoTurnWarning() {
        // 16 turns → info warning (> 15, ≤ 25) — informational, not actionable
        let entries = (0..<16).map { i in
            makeEntry(sessionId: "s1", input: 1000 * (i + 1), output: 100, timestamp: Date().addingTimeInterval(Double(i) * 60))
        }
        let result = monitor.assessCurrentSession(entries: entries)
        #expect(result != nil)
        #expect(result?.turnCount == 16)
        let turnWarnings = result!.warnings.filter { $0.message.contains("turns") }
        #expect(turnWarnings.count == 1)
        #expect(turnWarnings.first?.severity == .info)
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
        // Input:output ratio > 20:1 → info severity (informational, not actionable)
        let entries = [makeEntry(sessionId: "s1", input: 50_000, output: 100)]
        let result = monitor.assessCurrentSession(entries: entries)
        #expect(result != nil)
        let ratioWarnings = result!.warnings.filter { $0.message.contains("ratio") }
        #expect(ratioWarnings.count == 1)
        #expect(ratioWarnings.first?.severity == .info)
    }

    @Test func assess_normalRatio_noWarning() {
        let entries = [makeEntry(sessionId: "s1", input: 5_000, output: 2_000)]
        let result = monitor.assessCurrentSession(entries: entries)
        #expect(result != nil)
        let ratioWarnings = result!.warnings.filter { $0.message.contains("ratio") }
        #expect(ratioWarnings.isEmpty)
    }

    // MARK: - Multiple sessions (assessSessions)

    @Test func assessSessions_groupsBySessionId() {
        let entries = [
            makeEntry(sessionId: "s1", input: 1000, output: 100),
            makeEntry(sessionId: "s2", input: 2000, output: 200),
            makeEntry(sessionId: "s1", input: 1500, output: 150),
        ]
        let results = monitor.assessSessions(entries: entries, topLimit: 10)
        #expect(results.top.count == 2)
        let s1 = results.top.first { $0.id == "s1" }
        let s2 = results.top.first { $0.id == "s2" }
        #expect(s1 != nil)
        #expect(s2 != nil)
        #expect(s1?.turnCount == 2)
        #expect(s2?.turnCount == 1)
    }

    // MARK: - topSessions filtering/sorting

    @Test func assessSessions_currentSessionAlwaysInTop() {
        // Current session is idle past cutoff but should still appear in top
        let oldTime = Date().addingTimeInterval(-48 * 3600) // 48h ago
        let entries = [
            makeEntry(sessionId: "current", input: 50_000, output: 1_000, timestamp: oldTime),
        ]
        let results = monitor.assessSessions(entries: entries, topLimit: 5)
        // Current session (most recent by default) should be in top despite being old
        #expect(results.current != nil)
        #expect(results.top.contains { $0.id == "current" })
    }

    @Test func topSessions_excludesOldSessions() {
        let recentTime = Date()
        let oldTime = Date().addingTimeInterval(-48 * 3600) // 48h ago

        // Entries sorted by timestamp ascending (as SessionLogReader delivers them)
        let entries = [
            makeEntry(sessionId: "old", input: 2000, output: 200, timestamp: oldTime),
            makeEntry(sessionId: "recent", input: 1000, output: 100, timestamp: recentTime),
        ]
        let top = monitor.topSessions(entries: entries, limit: 5)
        // "recent" is current (entries.last) so always included; "old" excluded by 24h cutoff
        #expect(top.count == 1)
        #expect(top.first?.id == "recent")
    }

    @Test func topSessions_sortedByHighestUsage() {
        let now = Date()
        // s3 has highest input (most context consumed), then s2, then s1
        let entries = [
            makeEntry(sessionId: "s1", input: 1000, output: 100, timestamp: now.addingTimeInterval(-3600)),
            makeEntry(sessionId: "s2", input: 2000, output: 200, timestamp: now),
            makeEntry(sessionId: "s3", input: 3000, output: 300, timestamp: now.addingTimeInterval(-7200)),
        ]
        let top = monitor.topSessions(entries: entries, limit: 5)
        #expect(top.count == 3)
        // Sorted by usagePercentage descending (highest context usage first)
        #expect(top[0].id == "s3")
        #expect(top[1].id == "s2")
        #expect(top[2].id == "s1")
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
        // totalUsed = 10K + 500 latestOutput = 10.5K, duration = 2 min → ~5250/min
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

    // MARK: - Anomaly detection

    @Test func assess_zeroOutput_manyTurns() {
        // 5 turns with zero output → warning
        let entries = (0..<5).map { i in
            makeEntry(sessionId: "s1", input: 1000 * (i + 1), output: 0, timestamp: Date().addingTimeInterval(Double(i) * 120))
        }
        let result = monitor.assessCurrentSession(entries: entries)
        #expect(result != nil)
        let zeroOutputWarnings = result!.warnings.filter { $0.message.contains("No output") }
        #expect(zeroOutputWarnings.count == 1)
        #expect(zeroOutputWarnings.first?.severity == .strong)
    }

    @Test func assess_zeroOutput_fewTurns_noWarning() {
        // 2 turns with zero output → below threshold, no warning
        let entries = (0..<2).map { i in
            makeEntry(sessionId: "s1", input: 1000 * (i + 1), output: 0, timestamp: Date().addingTimeInterval(Double(i) * 120))
        }
        let result = monitor.assessCurrentSession(entries: entries)
        let zeroOutputWarnings = result!.warnings.filter { $0.message.contains("No output") }
        #expect(zeroOutputWarnings.isEmpty)
    }

    @Test func assess_staleSession_nonGreenBand() {
        // Session with last activity 45 min ago and orange band → stale warning
        // Need totalUsed > 60% of 1M = 600K for orange band
        let staleTime = Date().addingTimeInterval(-45 * 60)
        let entries = [
            makeEntry(sessionId: "s1", input: 590_000, output: 15_000, timestamp: staleTime.addingTimeInterval(-60)),
            makeEntry(sessionId: "s1", input: 595_000, output: 15_000, timestamp: staleTime),
        ]
        let result = monitor.assessCurrentSession(entries: entries)
        #expect(result != nil)
        let staleWarnings = result!.warnings.filter { $0.message.contains("idle") }
        #expect(staleWarnings.count == 1)
    }

    @Test func assess_staleSession_greenBand_noWarning() {
        // Green band session idle 45 min → no stale warning (green is fine)
        let staleTime = Date().addingTimeInterval(-45 * 60)
        let entries = [
            makeEntry(sessionId: "s1", input: 1_000, output: 100, timestamp: staleTime.addingTimeInterval(-60)),
            makeEntry(sessionId: "s1", input: 1_000, output: 100, timestamp: staleTime),
        ]
        let result = monitor.assessCurrentSession(entries: entries)
        let staleWarnings = result!.warnings.filter { $0.message.contains("idle") }
        #expect(staleWarnings.isEmpty)
    }

    @Test func assess_configThresholds_anomaly() {
        let config = TokenHealthConfig()
        #expect(config.staleSessionMinutes == 30)
        #expect(config.zeroOutputTurnThreshold == 3)
    }

    // MARK: - Custom config thresholds

    @Test func assess_customThresholds() {
        var config = TokenHealthConfig()
        config.greenThreshold = 30.0
        config.redThreshold = 50.0
        let customMonitor = TokenHealthMonitor(config: config)

        // 40% usage → with default would be green, with custom thresholds → orange
        // usable window = 1M. 40% = 400K.
        let entries = [makeEntry(sessionId: "s1", input: 395_000, output: 5_000)]
        let result = customMonitor.assessCurrentSession(entries: entries)
        #expect(result?.band == .orange)
    }

    // MARK: - Rapid consumption

    @Test func assess_rapidConsumption_triggered() {
        // 2 entries within 30 seconds, high token usage → warning
        let start = Date()
        let entries = [
            makeEntry(sessionId: "s1", input: 40_000, output: 15_000, timestamp: start),
            makeEntry(sessionId: "s1", input: 45_000, output: 15_000, timestamp: start.addingTimeInterval(30)),
        ]
        let result = monitor.assessCurrentSession(entries: entries)
        #expect(result != nil)
        let rapidWarnings = result!.warnings.filter { $0.message.contains("Rapid") }
        #expect(rapidWarnings.count == 1)
    }

    @Test func assess_rapidConsumption_notTriggered_longSession() {
        // 2 entries over 2 minutes — not rapid
        let start = Date()
        let entries = [
            makeEntry(sessionId: "s1", input: 40_000, output: 15_000, timestamp: start),
            makeEntry(sessionId: "s1", input: 45_000, output: 15_000, timestamp: start.addingTimeInterval(120)),
        ]
        let result = monitor.assessCurrentSession(entries: entries)
        #expect(result != nil)
        let rapidWarnings = result!.warnings.filter { $0.message.contains("Rapid") }
        #expect(rapidWarnings.isEmpty)
    }

    @Test func assess_rapidConsumption_customConfig() {
        var config = TokenHealthConfig()
        config.rapidConsumptionSeconds = 120
        config.rapidConsumptionTokens = 10_000
        let customMonitor = TokenHealthMonitor(config: config)

        let start = Date()
        let entries = [
            makeEntry(sessionId: "s1", input: 8_000, output: 5_000, timestamp: start),
            makeEntry(sessionId: "s1", input: 10_000, output: 5_000, timestamp: start.addingTimeInterval(90)),
        ]
        let result = customMonitor.assessCurrentSession(entries: entries)
        #expect(result != nil)
        let rapidWarnings = result!.warnings.filter { $0.message.contains("Rapid") }
        #expect(rapidWarnings.count == 1)
    }

    // MARK: - Velocity with custom config

    @Test func assess_velocity_customMinDuration() {
        var config = TokenHealthConfig()
        config.velocityMinDuration = 30
        let customMonitor = TokenHealthMonitor(config: config)

        let start = Date()
        let entries = [
            makeEntry(sessionId: "s1", input: 5_000, output: 500, timestamp: start),
            makeEntry(sessionId: "s1", input: 10_000, output: 500, timestamp: start.addingTimeInterval(45)),
        ]
        let result = customMonitor.assessCurrentSession(entries: entries)
        // With default config (60s min), 45s session → no velocity.
        // With custom 30s min, 45s > 30s → velocity calculated.
        #expect(result?.tokensPerMinute != nil)
    }

    // MARK: - Config defaults for new fields

    @Test func configDefaults_rapidConsumptionAndVelocity() {
        let config = TokenHealthConfig.default
        #expect(config.rapidConsumptionSeconds == 60)
        #expect(config.rapidConsumptionTokens == 50_000)
        #expect(config.velocityMinDuration == 60)
    }

    // MARK: - Context window tier adjustment

    @Test func contextWindow_noDownward_150K_stays_1M() {
        // Model default: 1M. Observed 150K tokens — no downgrade (upward-only adjustment)
        let entries = [makeEntry(sessionId: "s1", input: 149_000, output: 1_000)]
        let result = monitor.assessCurrentSession(entries: entries)
        #expect(result != nil)
        #expect(result?.contextWindow == 1_000_000)
    }

    @Test func contextWindow_noDownward_50K_stays_1M() {
        // Model default: 1M. Very small session — no downgrade (low tokens = early session, not smaller window)
        let entries = [makeEntry(sessionId: "s1", input: 49_000, output: 1_000)]
        let result = monitor.assessCurrentSession(entries: entries)
        #expect(result != nil)
        #expect(result?.contextWindow == 1_000_000)
    }

    @Test func contextWindow_upwardAdjustment_1_2M_to_2M() {
        // Model default: 1M. Observed 1.2M tokens → upward adjustment to 2M tier
        let entries = [makeEntry(sessionId: "s1", input: 1_199_000, output: 1_000)]
        let result = monitor.assessCurrentSession(entries: entries)
        #expect(result != nil)
        #expect(result?.contextWindow == 2_000_000)
    }

    // MARK: - Division by zero safety

    @Test func assess_zeroTokens_validPercentage() {
        // Zero tokens with a normal context window should produce 0% (not NaN).
        // Note: Can't easily test zero contextWindow since it's derived from model lookup,
        // but the guard at TokenHealthMonitor:148 (usableWindow > 0) covers that path.
        let entries = [makeEntry(sessionId: "s1", input: 0, output: 0)]
        let result = monitor.assessCurrentSession(entries: entries)
        if let result {
            #expect(!result.usagePercentage.isNaN)
            #expect(!result.usagePercentage.isInfinite)
            #expect(result.usagePercentage >= 0)
        }
    }

    @Test func assess_unknownModel_validResult() {
        // Unknown model gets default 1M context window — verify no crash
        let entries = [makeEntry(sessionId: "s1", input: 50_000, output: 5_000, model: "unknown-model-xyz")]
        let result = monitor.assessCurrentSession(entries: entries)
        if let result {
            #expect(!result.usagePercentage.isNaN)
            #expect(result.contextWindow > 0)
        }
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
            gitBranch: gitBranch,
            toolCallCount: 0
        )
    }
}
