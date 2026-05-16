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
            sessionDuration: 3_600,
            lastActivity: Date(),
            tokensPerMinute: 1_500
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
        let health = makeHealth(band: .green, lastActivity: Date().addingTimeInterval(-3_600))
        #expect(SessionInfoFormatter.staleIdleMinutes(for: health) == nil)
    }

    @Test func staleIdleMinutes_nilForRecentActivity() {
        let health = makeHealth(band: .orange, lastActivity: Date().addingTimeInterval(-60))
        #expect(SessionInfoFormatter.staleIdleMinutes(for: health) == nil)
    }

    @Test func staleIdleMinutes_returnsMinutesWhenStale() {
        let health = makeHealth(band: .orange, lastActivity: Date().addingTimeInterval(-3_600))
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
        let health = makeHealth(totalUsed: 50_000, usableWindow: 160_000)
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
        let result = SessionInfoFormatter.formatSessionTime(Date().addingTimeInterval(-7_200))
        #expect(result.hasPrefix("Today"))
    }

    // MARK: - Copyable details

    @Test func copyableDetails_includesHeader() {
        let health = makeHealth()
        let text = SessionInfoFormatter.copyableDetails(for: health)
        #expect(text.contains("Context Health"))
        #expect(text.contains("─────────────"))
    }

    @Test func copyableDetails_includesSessionId() {
        let health = makeHealth(id: "abc-12345")
        let text = SessionInfoFormatter.copyableDetails(for: health)
        #expect(text.contains("Session:  abc-12345"))
    }

    @Test func copyableDetails_includesModel() {
        let health = makeHealth(model: "claude-sonnet-4-5-20250929")
        let text = SessionInfoFormatter.copyableDetails(for: health)
        #expect(text.contains("Model:"))
    }

    @Test func copyableDetails_includesProjectAndBranch() {
        let health = makeHealth(projectName: "MyApp", gitBranch: "feat/login")
        let text = SessionInfoFormatter.copyableDetails(for: health)
        #expect(text.contains("Project:  MyApp"))
        #expect(text.contains("Branch:   feat/login"))
    }

    @Test func copyableDetails_includesExactTokenCounts() {
        let health = makeHealth(totalUsed: 50_000, usableWindow: 160_000)
        let text = SessionInfoFormatter.copyableDetails(for: health)
        #expect(text.contains("Context:  50000/160000"))
    }

    @Test func copyableDetails_omitsEmptyFields() {
        let health = makeHealth(id: "", model: "", projectName: nil, gitBranch: nil)
        let text = SessionInfoFormatter.copyableDetails(for: health)
        #expect(!text.contains("Session:"))
        #expect(!text.contains("Model:"))
        #expect(!text.contains("Project:"))
        #expect(!text.contains("Branch:"))
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
        usableWindow: Int = 160_000
    ) -> TokenHealthStatus {
        TokenHealthStatus(
            id: id,
            band: band,
            usagePercentage: 0,
            totalUsed: totalUsed,
            contextWindow: 200_000,
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
