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

    // MARK: - Extended context window lookup

    @Test func contextWindow_allKnownModels() {
        // Every model in contextWindows should return 200_000
        let models = [
            "claude-opus-4-6",
            "claude-sonnet-4-5-20250929",
            "claude-haiku-4-5-20251001",
            "claude-3-5-sonnet-20241022",
            "claude-3-5-haiku-20241022",
            "claude-3-opus-20240229",
            "claude-3-sonnet-20240229",
            "claude-3-haiku-20240307",
        ]
        for model in models {
            #expect(
                TokenHealthConfig.contextWindow(for: model) == 200_000,
                "Expected 200K for \(model)"
            )
        }
    }

    @Test func contextWindow_prefixMatch_futureDate() {
        // Same model family with a different date suffix should match via prefix
        #expect(TokenHealthConfig.contextWindow(for: "claude-sonnet-4-5-20260101") == 200_000)
    }

    @Test func contextWindow_prefixMatch_haiku35_futureDate() {
        #expect(TokenHealthConfig.contextWindow(for: "claude-3-5-haiku-20260101") == 200_000)
    }

    @Test func contextWindow_noHyphen_returnsFallback() {
        #expect(TokenHealthConfig.contextWindow(for: "gpt4") == TokenHealthConfig.defaultContextWindow)
    }

    // MARK: - Config thresholds validation

    @Test func defaultConfig_greenBelowRed() {
        let config = TokenHealthConfig.default
        #expect(config.greenThreshold < config.redThreshold)
    }

    @Test func defaultConfig_turnCountMildBelowStrong() {
        let config = TokenHealthConfig.default
        #expect(config.turnCountMild < config.turnCountStrong)
    }
}
