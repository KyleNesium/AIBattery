import Testing
@testable import AIBatteryCore

@Suite("ModelNameMapper")
struct ModelNameMapperTests {

    // MARK: - Standard model families

    @Test func displayName_opus() {
        #expect(ModelNameMapper.displayName(for: "claude-opus-4-6") == "Opus 4.6")
    }

    @Test func displayName_sonnet() {
        #expect(ModelNameMapper.displayName(for: "claude-sonnet-4-5-20250929") == "Sonnet 4.5")
    }

    @Test func displayName_haiku() {
        #expect(ModelNameMapper.displayName(for: "claude-haiku-4-5-20251001") == "Haiku 4.5")
    }

    // MARK: - Older models (3.x)

    @Test func displayName_claude3_5Sonnet() {
        // "3-5-sonnet" → family "3", version "5.sonnet" → "3 5.sonnet"
        #expect(ModelNameMapper.displayName(for: "claude-3-5-sonnet-20241022") == "3 5.sonnet")
    }

    @Test func displayName_claude3Opus() {
        // "3-opus" → family "3", version "opus" → "3 opus"
        #expect(ModelNameMapper.displayName(for: "claude-3-opus-20240229") == "3 opus")
    }

    @Test func displayName_claude3Haiku() {
        // "3-haiku" → family "3", version "haiku" → "3 haiku"
        #expect(ModelNameMapper.displayName(for: "claude-3-haiku-20240307") == "3 haiku")
    }

    // MARK: - Edge cases

    @Test func displayName_emptyString() {
        #expect(ModelNameMapper.displayName(for: "") == "Unknown")
    }

    @Test func displayName_noPrefix() {
        // Model without claude- prefix: "gpt-4" → family "Gpt", version "4" → "Gpt 4"
        #expect(ModelNameMapper.displayName(for: "gpt-4") == "Gpt 4")
    }

    @Test func displayName_onlyDateSuffix() {
        // "claude-20250101" → strip "claude-" → "20250101"
        // Date regex looks for "-\d{8}", but "20250101" has no leading dash → stays as-is
        // Split → ["20250101"], family "20250101", no version → "20250101"
        #expect(ModelNameMapper.displayName(for: "claude-20250101") == "20250101")
    }

    @Test func displayName_noDash_singleFamily() {
        // Just "claude-opus" with no version segments
        #expect(ModelNameMapper.displayName(for: "claude-opus") == "Opus")
    }
}
