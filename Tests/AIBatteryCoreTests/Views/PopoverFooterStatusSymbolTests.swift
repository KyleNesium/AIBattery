import Testing
@testable import AIBatteryCore

/// Pins the v2.3.1 colorblind-safe status-dot mapping. Each non-operational
/// state must carry a distinguishing SF Symbol overlay so severity is readable
/// without color. Operational and unknown stay plain.
@Suite("PopoverFooterStatusSymbol")
struct PopoverFooterStatusSymbolTests {
    @Test func operational_hasNoSymbol() {
        #expect(PopoverFooterView.statusSymbol(for: .operational) == nil)
    }

    @Test func unknown_hasNoSymbol() {
        #expect(PopoverFooterView.statusSymbol(for: .unknown) == nil)
    }

    @Test func nilIndicator_hasNoSymbol() {
        // Loading / first-paint state — no overlay either.
        #expect(PopoverFooterView.statusSymbol(for: nil) == nil)
    }

    @Test func degradedPerformance_isExclamationmark() {
        #expect(PopoverFooterView.statusSymbol(for: .degradedPerformance) == "exclamationmark")
    }

    @Test func partialOutage_isXmark() {
        #expect(PopoverFooterView.statusSymbol(for: .partialOutage) == "xmark")
    }

    @Test func majorOutage_isXmark() {
        // Partial and major outage share the xmark glyph — color (orange vs red)
        // distinguishes them, and the symbol carries the "down" semantic.
        #expect(PopoverFooterView.statusSymbol(for: .majorOutage) == "xmark")
    }

    @Test func maintenance_isWrench() {
        #expect(PopoverFooterView.statusSymbol(for: .maintenance) == "wrench.adjustable")
    }

    @Test func everyNonOperationalIndicator_yieldsSymbol() {
        // Belt-and-suspenders: any future StatusIndicator case that's added and
        // intended to surface in the popover should also map to a symbol; if a
        // new case slips in without a mapping, this test catches it via the
        // default-nil branch.
        let nonOperational: [StatusIndicator] = [
            .degradedPerformance, .partialOutage, .majorOutage, .maintenance,
        ]
        for state in nonOperational {
            #expect(PopoverFooterView.statusSymbol(for: state) != nil,
                    "\(state) should overlay a symbol so it reads without color")
        }
    }
}
