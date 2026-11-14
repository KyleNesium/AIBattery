import Testing
@testable import AIBatteryCore

@Suite("TokenHealthConfig")
struct TokenHealthConfigTests {
    // MARK: - Context window lookup

    @Test func contextWindow_exactMatch() {
        #expect(TokenHealthConfig.contextWindow(for: "claude-opus-4-6") == 1_000_000)
    }

    @Test func contextWindow_datedModel() {
        #expect(TokenHealthConfig.contextWindow(for: "claude-sonnet-4-5-20250929") == 200_000)
    }

    @Test func contextWindow_prefixMatch() {
        // Should match "claude-3-5-sonnet-*" via prefix — 3.x models retain 200K
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
        #expect(TokenHealthConfig.usableContextRatio == 1.0)
    }

    @Test func defaultContextWindow() {
        #expect(TokenHealthConfig.defaultContextWindow == 1_000_000)
    }

    // MARK: - Extended context window lookup

    /// Anthropic's models overview, 2026-11-14: 1M from the 4.6 generation on.
    @Test func contextWindow_fromFourPointSixOn_isOneMillion() {
        let models = [
            "claude-opus-4-6",
            "claude-sonnet-4-6-20250929",
            "claude-opus-4-7",
            "claude-opus-4-8",
            "claude-opus-5",
            "claude-sonnet-5",
            "claude-fable-5-1",
            "claude-fable-5-2",
            "claude-opus-5-5",
            "claude-sonnet-5-5",
            "claude-haiku-5-5",
            // Not released when this was written: a new model needs no table entry.
            "claude-fable-5-3",
            "claude-opus-6",
        ]
        for model in models {
            #expect(
                TokenHealthConfig.contextWindow(for: model) == 1_000_000,
                "Expected 1M for \(model)"
            )
        }
    }

    /// Regression (3.5.0): a table gave every 4.x model 1M, so a Haiku 4.5 or Sonnet 4.5
    /// session read as a fifth as full as it was. The 4.5 generation has 200K.
    @Test func contextWindow_beforeFourPointSix_isTwoHundredThousand() {
        let models = [
            "claude-opus-4-5",
            "claude-sonnet-4-5-20250929",
            "claude-haiku-4-5-20251001",
            "claude-opus-4-1-20250805",
            "claude-opus-4-20250514",
            "claude-sonnet-4-20250514",
        ]
        for model in models {
            #expect(
                TokenHealthConfig.contextWindow(for: model) == 200_000,
                "Expected 200K for \(model)"
            )
        }
    }

    @Test func contextWindow_allKnownModels_3x() {
        // Claude 3.x models retain 200K context windows
        let models = [
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
        #expect(TokenHealthConfig.contextWindow(for: "claude-sonnet-4-6-20260101") == 1_000_000)
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

    // MARK: - OpenAI (Codex) models

    @Test func contextWindow_gptFamily_usesCodexReportedWindow() {
        #expect(TokenHealthConfig.contextWindow(for: "gpt-5.4") == 258_400)
        #expect(TokenHealthConfig.contextWindow(for: "gpt-5.6-sol") == 258_400)
        #expect(TokenHealthConfig.openAIDefaultContextWindow == 258_400)
    }

    @Test func contextWindow_unknownNonGPT_stillDefaultsToOneMillion() {
        #expect(TokenHealthConfig.contextWindow(for: "something-else") == TokenHealthConfig.defaultContextWindow)
    }
}
