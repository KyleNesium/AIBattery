import Testing
@testable import AIBatteryCore

@Suite("TokenHealthConfig")
struct TokenHealthConfigTests {

    // MARK: - Context window lookup

    @Test func contextWindow_exactMatch() {
        #expect(TokenHealthConfig.contextWindow(for: "claude-opus-4-6") == 200_000)
    }

    @Test func contextWindow_datedModel() {
        #expect(TokenHealthConfig.contextWindow(for: "claude-sonnet-4-5-20250929") == 200_000)
    }

    @Test func contextWindow_prefixMatch() {
        // Should match "claude-3-5-sonnet-*" via prefix
        #expect(TokenHealthConfig.contextWindow(for: "claude-3-5-sonnet-20241022") == 200_000)
    }

    @Test func contextWindow_unknownModelReturnsFallback() {
        #expect(TokenHealthConfig.contextWindow(for: "claude-unknown-99") == TokenHealthConfig.defaultContextWindow)
    }

    @Test func contextWindow_emptyStringReturnsFallback() {
        #expect(TokenHealthConfig.contextWindow(for: "") == TokenHealthConfig.defaultContextWindow)
    }

    // MARK: - Default config values

    @Test func defaultConfig_thresholds() {
        let config = TokenHealthConfig.default
        #expect(config.greenThreshold == 60.0)
        #expect(config.redThreshold == 80.0)
        #expect(config.turnCountMild == 15)
        #expect(config.turnCountStrong == 25)
        #expect(config.inputOutputRatioThreshold == 20.0)
    }

    @Test func usableContextRatio() {
        #expect(TokenHealthConfig.usableContextRatio == 0.80)
    }

    @Test func defaultContextWindow() {
        #expect(TokenHealthConfig.defaultContextWindow == 200_000)
    }
}
