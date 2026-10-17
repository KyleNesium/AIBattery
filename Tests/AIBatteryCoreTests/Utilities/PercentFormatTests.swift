import Testing
@testable import AIBatteryCore

@Suite("PercentFormat — one truncating rule for every surface (A13)")
struct PercentFormatTests {
    @Test("99.6 truncates to 99% — 100% means the window really is full")
    func nearlyFullIsNotFull() {
        #expect(PercentFormat.display(99.6) == "99%")
        #expect(PercentFormat.display(99.999) == "99%")
    }

    @Test("exactly 100 and above read 100%")
    func fullReadsFull() {
        #expect(PercentFormat.display(100.0) == "100%")
        #expect(PercentFormat.display(104.2) == "104%")
    }

    @Test("0.4 truncates to 0%")
    func nearlyEmptyIsEmpty() {
        #expect(PercentFormat.display(0.4) == "0%")
        #expect(PercentFormat.display(0) == "0%")
    }

    @Test("never rounds up at the .5 boundary")
    func halfDoesNotRoundUp() {
        #expect(PercentFormat.display(42.5) == "42%")
        #expect(PercentFormat.whole(42.5) == 42)
    }

    @Test("float noise from utilization × 100 does not knock a whole percent down")
    func floatNoiseIsSnapped() {
        // 0.57 * 100 == 56.99999999999999 in Double; a bare Int() would read 56.
        #expect(PercentFormat.display(0.57 * 100) == "57%")
        #expect(PercentFormat.display(0.29 * 100) == "29%")
        #expect(PercentFormat.display(0.07 * 100) == "7%")
    }

    @Test("negative and non-finite inputs clamp to 0 instead of trapping")
    func degenerateInputs() {
        #expect(PercentFormat.display(-3) == "0%")
        #expect(PercentFormat.display(.nan) == "0%")
        #expect(PercentFormat.display(.infinity) == "0%")
    }

    @Test("spoken form matches the displayed whole number")
    func spokenMatchesDisplay() {
        #expect(PercentFormat.spoken(99.6) == "99 percent")
    }

    @Test("remaining is consistent with the displayed number: 99% shown → 1 percent remaining")
    func remainingAgreesWithDisplay() {
        #expect(PercentFormat.remaining(99.6) == 1)
        #expect(PercentFormat.remaining(100) == 0)
        #expect(PercentFormat.remaining(130) == 0)
        #expect(PercentFormat.remaining(0.4) == 100)
    }
}
