import Testing
@testable import AIBatteryCore

@Suite("TokenFormatter")
struct TokenFormatterTests {

    // MARK: - Sub-1K (raw number)

    @Test func format_zero() {
        #expect(TokenFormatter.format(0) == "0")
    }

    @Test func format_smallNumber() {
        #expect(TokenFormatter.format(500) == "500")
    }

    @Test func format_justBelow1K() {
        #expect(TokenFormatter.format(999) == "999")
    }

    // MARK: - Thousands (K)

    @Test func format_exactly1K() {
        #expect(TokenFormatter.format(1_000) == "1.0K")
    }

    @Test func format_2500() {
        #expect(TokenFormatter.format(2_500) == "2.5K")
    }

    @Test func format_10K() {
        // 10K and above: no decimal
        #expect(TokenFormatter.format(10_000) == "10K")
    }

    @Test func format_15K() {
        #expect(TokenFormatter.format(15_000) == "15K")
    }

    @Test func format_999K() {
        #expect(TokenFormatter.format(999_999) == "1000K")
    }

    // MARK: - Millions (M)

    @Test func format_exactly1M() {
        #expect(TokenFormatter.format(1_000_000) == "1.0M")
    }

    @Test func format_3_2M() {
        #expect(TokenFormatter.format(3_200_000) == "3.2M")
    }

    @Test func format_10M() {
        // 10M and above: no decimal
        #expect(TokenFormatter.format(10_000_000) == "10M")
    }

    @Test func format_150M() {
        #expect(TokenFormatter.format(150_000_000) == "150M")
    }

    // MARK: - Edge cases

    @Test func format_1() {
        #expect(TokenFormatter.format(1) == "1")
    }

    @Test func format_negativeReturnsZero() {
        #expect(TokenFormatter.format(-1) == "0")
        #expect(TokenFormatter.format(-999) == "0")
        #expect(TokenFormatter.format(-1_000_000) == "0")
    }

    @Test func format_boundaryAt1K() {
        #expect(TokenFormatter.format(999) == "999")
        #expect(TokenFormatter.format(1_000) == "1.0K")
    }

    @Test func format_boundaryAt10K() {
        #expect(TokenFormatter.format(9_999) == "10.0K")
        #expect(TokenFormatter.format(10_000) == "10K")
    }

    @Test func format_boundaryAt1M() {
        #expect(TokenFormatter.format(999_999) == "1000K")
        #expect(TokenFormatter.format(1_000_000) == "1.0M")
    }

    @Test func format_boundaryAt10M() {
        #expect(TokenFormatter.format(9_999_999) == "10.0M")
        #expect(TokenFormatter.format(10_000_000) == "10M")
    }
}
