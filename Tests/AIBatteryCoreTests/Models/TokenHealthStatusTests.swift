import Testing
import Foundation
@testable import AIBatteryCore

@Suite("TokenHealthStatus")
struct TokenHealthStatusTests {

    // MARK: - HealthBand raw values

    @Test func healthBand_rawValues() {
        #expect(HealthBand.green.rawValue == "Optimal")
        #expect(HealthBand.orange.rawValue == "Warning")
        #expect(HealthBand.red.rawValue == "Critical")
        #expect(HealthBand.unknown.rawValue == "No Data")
    }

    // MARK: - suggestedAction

    @Test func suggestedAction_green() {
        let status = makeStatus(band: .green)
        #expect(status.suggestedAction == nil)
    }

    @Test func suggestedAction_orange() {
        let status = makeStatus(band: .orange)
        #expect(status.suggestedAction != nil)
        #expect(status.suggestedAction!.contains("trimming"))
    }

    @Test func suggestedAction_red() {
        let status = makeStatus(band: .red)
        #expect(status.suggestedAction != nil)
        #expect(status.suggestedAction!.contains("new conversation"))
    }

    @Test func suggestedAction_unknown() {
        let status = makeStatus(band: .unknown)
        #expect(status.suggestedAction == nil)
    }

    // MARK: - Helper

    private func makeStatus(band: HealthBand) -> TokenHealthStatus {
        TokenHealthStatus(
            id: "test-session",
            band: band,
            usagePercentage: 50,
            totalUsed: 80_000,
            contextWindow: 200_000,
            usableWindow: 160_000,
            remainingTokens: 80_000,
            inputTokens: 50_000,
            outputTokens: 20_000,
            cacheReadTokens: 5_000,
            cacheWriteTokens: 5_000,
            model: "claude-opus-4-6",
            turnCount: 10,
            warnings: [],
            tokensPerMinute: nil,
            projectName: nil,
            gitBranch: nil,
            sessionStart: nil,
            sessionDuration: nil,
            lastActivity: nil
        )
    }
}
