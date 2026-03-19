import Testing
import SwiftUI
@testable import AIBatteryCore

@Suite("Spacing")
struct SpacingTests {
    @Test func tight_is2() { #expect(Spacing.tight == 2) }
    @Test func small_is4() { #expect(Spacing.small == 4) }
    @Test func gap_is6() { #expect(Spacing.gap == 6) }
    @Test func section_is8() { #expect(Spacing.section == 8) }
    @Test func sectionHorizontal_is16() { #expect(Spacing.sectionHorizontal == 16) }
    @Test func overlay_is24() { #expect(Spacing.overlay == 24) }
}

@Suite("Layout")
struct LayoutTests {
    @Test func popoverWidth_is275() { #expect(Layout.popoverWidth == 275) }
    @Test func chartHeight_is50() { #expect(Layout.chartHeight == 50) }
    @Test func barHeight_is8() { #expect(Layout.barHeight == 8) }
    @Test func barCornerRadius_is3() { #expect(Layout.barCornerRadius == 3) }
    @Test func chevronFrame_is22() { #expect(Layout.chevronFrame == 22) }
    @Test func dotSize_is8() { #expect(Layout.dotSize == 8) }
    @Test func dotSizeSmall_is6() { #expect(Layout.dotSizeSmall == 6) }
}

@Suite("MotionConstants")
struct MotionConstantsTests {
    @Test func standard_isDefined() {
        let anim = MotionConstants.standard
        #expect(anim == .easeOut(duration: 0.15))
    }

    @Test func snappy_isDefined() {
        let anim = MotionConstants.snappy
        #expect(anim == .easeOut(duration: 0.1))
    }
}
