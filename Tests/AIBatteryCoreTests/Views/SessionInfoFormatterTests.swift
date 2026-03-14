import Testing
import Foundation
@testable import AIBatteryCore

@Suite("SessionInfoFormatter")
struct SessionInfoFormatterTests {

    // MARK: - Label parts

    @Test func labelParts_projectAndBranch() {
        let health = makeHealth(projectName: "MyApp", gitBranch: "main")
        let parts = SessionInfoFormatter.labelParts(for: health)
        #expect(parts == ["MyApp", "main"])
    }

    @Test func labelParts_projectOnly() {
        let health = makeHealth(projectName: "MyApp", gitBranch: nil)
        let parts = SessionInfoFormatter.labelParts(for: health)
        #expect(parts == ["MyApp"])
    }

    @Test func labelParts_skipsHEADBranch() {
        let health = makeHealth(projectName: "MyApp", gitBranch: "HEAD")
        let parts = SessionInfoFormatter.labelParts(for: health)
        #expect(parts == ["MyApp"])
    }

    @Test func labelParts_skipsEmptyBranch() {
        let health = makeHealth(projectName: "MyApp", gitBranch: "")
        let parts = SessionInfoFormatter.labelParts(for: health)
        #expect(parts == ["MyApp"])
    }

    @Test func labelParts_empty() {
        let health = makeHealth(projectName: nil, gitBranch: nil)
        let parts = SessionInfoFormatter.labelParts(for: health)
        #expect(parts.isEmpty)
    }

    // MARK: - ID prefix

    @Test func idPrefix_truncatesTo8Chars() {
        let health = makeHealth(id: "abcdef1234567890")
        #expect(SessionInfoFormatter.idPrefix(for: health) == "abcdef12")
    }

    @Test func idPrefix_nilForEmptyId() {
        let health = makeHealth(id: "")
        #expect(SessionInfoFormatter.idPrefix(for: health) == nil)
    }

    @Test func idPrefix_shortIdUnchanged() {
        let health = makeHealth(id: "abc")
        #expect(SessionInfoFormatter.idPrefix(for: health) == "abc")
    }

    // MARK: - Bottom parts

    @Test func bottomParts_includesDurationAndVelocity() {
        let health = makeHealth(
            sessionDuration: 3600,
            lastActivity: Date(),
            tokensPerMinute: 1500
        )
        let parts = SessionInfoFormatter.bottomParts(for: health)
        #expect(parts.count == 3)
        #expect(parts[0] == "1h 0m") // DurationFormatter.compact(3600)
        #expect(parts[2] == "1.5K/min")
    }

    @Test func bottomParts_emptyWhenNoMetadata() {
        let health = makeHealth()
        let parts = SessionInfoFormatter.bottomParts(for: health)
        #expect(parts.isEmpty)
    }

    @Test func bottomParts_fallsBackToSessionStart() {
        let health = makeHealth(
            sessionStart: Date(),
            lastActivity: nil
        )
        let parts = SessionInfoFormatter.bottomParts(for: health)
        #expect(parts.count == 1)
        #expect(parts[0].contains("just now") || parts[0].contains("Today"))
    }

    // MARK: - Stale idle minutes

    @Test func staleIdleMinutes_nilForGreenBand() {
        let health = makeHealth(band: .green, lastActivity: Date().addingTimeInterval(-3600))
        #expect(SessionInfoFormatter.staleIdleMinutes(for: health) == nil)
    }

    @Test func staleIdleMinutes_nilForRecentActivity() {
        let health = makeHealth(band: .orange, lastActivity: Date().addingTimeInterval(-60))
        #expect(SessionInfoFormatter.staleIdleMinutes(for: health) == nil)
    }

    @Test func staleIdleMinutes_returnsMinutesWhenStale() {
        let health = makeHealth(band: .orange, lastActivity: Date().addingTimeInterval(-3600))
        let minutes = SessionInfoFormatter.staleIdleMinutes(for: health)
        #expect(minutes == 60)
    }

    // MARK: - Detail tooltip

    @Test func detailTooltip_includesSessionId() {
        let health = makeHealth(id: "test-session-123")
        let tooltip = SessionInfoFormatter.detailTooltip(for: health)
        #expect(tooltip.contains("Session: test-session-123"))
    }

    @Test func detailTooltip_includesModel() {
        let health = makeHealth(model: "claude-opus-4-6-20250929")
        let tooltip = SessionInfoFormatter.detailTooltip(for: health)
        #expect(tooltip.contains("Model: Opus 4.6"))
    }

    @Test func detailTooltip_includesContext() {
        let health = makeHealth(totalUsed: 50000, usableWindow: 160000)
        let tooltip = SessionInfoFormatter.detailTooltip(for: health)
        #expect(tooltip.contains("Context:"))
    }

    // MARK: - Time formatting

    @Test func formatSessionTime_justNow() {
        let result = SessionInfoFormatter.formatSessionTime(Date())
        #expect(result == "just now")
    }

    @Test func formatSessionTime_minutesAgo() {
        let result = SessionInfoFormatter.formatSessionTime(Date().addingTimeInterval(-300))
        #expect(result == "5m ago")
    }

    @Test func formatSessionTime_todayShowsTime() {
        let result = SessionInfoFormatter.formatSessionTime(Date().addingTimeInterval(-7200))
        #expect(result.hasPrefix("Today"))
    }

    // MARK: - Helpers

    private func makeHealth(
        id: String = "session-1",
        band: HealthBand = .green,
        model: String = "",
        projectName: String? = nil,
        gitBranch: String? = nil,
        sessionStart: Date? = nil,
        sessionDuration: TimeInterval? = nil,
        lastActivity: Date? = nil,
        tokensPerMinute: Double? = nil,
        totalUsed: Int = 0,
        usableWindow: Int = 160000
    ) -> TokenHealthStatus {
        TokenHealthStatus(
            id: id,
            band: band,
            usagePercentage: 0,
            totalUsed: totalUsed,
            contextWindow: 200000,
            usableWindow: usableWindow,
            remainingTokens: usableWindow - totalUsed,
            inputTokens: 0,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheWriteTokens: 0,
            model: model,
            turnCount: 0,
            warnings: [],
            tokensPerMinute: tokensPerMinute,
            projectName: projectName,
            gitBranch: gitBranch,
            sessionStart: sessionStart,
            sessionDuration: sessionDuration,
            lastActivity: lastActivity
        )
    }
}
