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
        // "3-5-sonnet" → version "3.5", family "Sonnet" → "Sonnet 3.5"
        #expect(ModelNameMapper.displayName(for: "claude-3-5-sonnet-20241022") == "Sonnet 3.5")
    }

    @Test func displayName_claude3Opus() {
        // "3-opus" → version "3", family "Opus" → "Opus 3"
        #expect(ModelNameMapper.displayName(for: "claude-3-opus-20240229") == "Opus 3")
    }

    @Test func displayName_claude3Haiku() {
        // "3-haiku" → version "3", family "Haiku" → "Haiku 3"
        #expect(ModelNameMapper.displayName(for: "claude-3-haiku-20240307") == "Haiku 3")
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

    // MARK: - Additional edge cases

    @Test func displayName_multipleHyphens() {
        // "claude-3-5-haiku-20241022" → strip "claude-" → "3-5-haiku-20241022" → strip date → "3-5-haiku"
        #expect(ModelNameMapper.displayName(for: "claude-3-5-haiku-20241022") == "Haiku 3.5")
    }

    @Test func displayName_justClaude() {
        // "claude" → strip "claude-" doesn't match (no hyphen after) → stays "claude"
        #expect(ModelNameMapper.displayName(for: "claude") == "Claude")
    }

    @Test func displayName_longVersionSegments() {
        // Future model: "claude-titan-10-3-2-20260101"
        #expect(ModelNameMapper.displayName(for: "claude-titan-10-3-2-20260101") == "Titan 10.3.2")
    }

    // MARK: - Date stripping

    @Test func displayName_stripsDateWithExtraSuffix() {
        // Some models have date + extra suffix like "-latest"
        #expect(ModelNameMapper.displayName(for: "claude-sonnet-4-5-20250929-latest") == "Sonnet 4.5")
    }

    @Test func displayName_shortDateNotStripped() {
        // Only 8+ digit dates should be stripped
        #expect(ModelNameMapper.displayName(for: "claude-opus-4-6") == "Opus 4.6")
    }

    // MARK: - Real-world model IDs

    @Test func displayName_claude3_5SonnetV2() {
        #expect(ModelNameMapper.displayName(for: "claude-3-5-sonnet-v2-20241022") == "Sonnet V2 3.5")
    }

    @Test func displayName_unknownFamily() {
        #expect(ModelNameMapper.displayName(for: "claude-mystery-1-0") == "Mystery 1.0")
    }

    @Test func displayName_singleVersion() {
        #expect(ModelNameMapper.displayName(for: "claude-sonnet-4") == "Sonnet 4")
    }
}
