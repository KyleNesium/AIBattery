import Testing
import SwiftUI
@testable import AIBatteryCore

@Suite("Spacing")
struct SpacingTests {
    @Test func tight_is2() {
        #expect(Spacing.tight == 2)
    }

    @Test func small_is4() {
        #expect(Spacing.small == 4)
    }

    @Test func gap_is6() {
        #expect(Spacing.gap == 6)
    }

    @Test func section_is8() {
        #expect(Spacing.section == 8)
    }

    @Test func sectionHorizontal_is16() {
        #expect(Spacing.sectionHorizontal == 16)
    }

    @Test func overlay_is24() {
        #expect(Spacing.overlay == 24)
    }
}

@Suite("Layout")
struct LayoutTests {
    @Test func popoverWidth_is275() {
        #expect(Layout.popoverWidth == 275)
    }

    @Test func chartHeight_is50() {
        #expect(Layout.chartHeight == 50)
    }

    @Test func barHeight_is8() {
        #expect(Layout.barHeight == 8)
    }

    @Test func barCornerRadius_is3() {
        #expect(Layout.barCornerRadius == 3)
    }

    @Test func chevronFrame_is22() {
        #expect(Layout.chevronFrame == 22)
    }

    @Test func dotSize_is8() {
        #expect(Layout.dotSize == 8)
    }

    @Test func dotSizeSmall_is6() {
        #expect(Layout.dotSizeSmall == 6)
    }
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

    @Test func fadeIn_isDefined() {
        // fadeIn was added during the v2.3.1 polish sprint (MarqueeText
        // cycling) — pin its shape so the cross-fade timing doesn't drift.
        let anim = MotionConstants.fadeIn
        #expect(anim == .easeIn(duration: 0.3))
    }

    @Test func fadeOut_matchesFadeIn() {
        // fadeIn/fadeOut should remain symmetric — same duration, mirrored curves.
        // Lets MarqueeText's "fade out → 0.35s settle → fade in" choreography stay tunable.
        #expect(MotionConstants.fadeOut == .easeOut(duration: 0.3))
        #expect(MotionConstants.fadeIn == .easeIn(duration: 0.3))
    }

    // MARK: - expandTransition: opacity-only contract

    @Test func expandTransition_isPlainOpacity_notMove() {
        // Regression pin for v2.3.1: the popover is an NSPanel that re-anchors
        // its top to the menu bar while resizing. A .move transition translates
        // the inserting view in the opposite direction of the panel resize and
        // reads as a "jump". expandTransition MUST stay .opacity-only.
        //
        // AnyTransition has no public structural API, but it's a value type and
        // .opacity has a stable equality footprint. We compare against a fresh
        // .opacity, which historically diff-equates in SwiftUI's internals.
        // If a future change recombines .move into the token, the snapshot
        // string below will diverge.
        let lhs = String(reflecting: MotionConstants.expandTransition)
        let rhs = String(reflecting: AnyTransition.opacity)
        #expect(lhs == rhs, "expandTransition diverged from plain .opacity — did someone recombine .move(edge:)? See token doc-comment.")
    }

    // MARK: - Marquee timing tokens

    @Test func marqueePauseSeconds_is0_5() {
        #expect(MotionConstants.marqueePauseSeconds == 0.5)
    }

    @Test func marqueeHoldSeconds_is3_0() {
        #expect(MotionConstants.marqueeHoldSeconds == 3.0)
    }

    @Test func marqueeRestartSeconds_is0_1() {
        #expect(MotionConstants.marqueeRestartSeconds == 0.1)
    }

    @Test func marqueeFadeSettleSeconds_is0_6() {
        #expect(MotionConstants.marqueeFadeSettleSeconds == 0.6)
    }

    @Test func marqueeScrollSpeed_is30() {
        #expect(MotionConstants.marqueeScrollSpeed == 30.0)
    }

    @Test func marqueeScroll_durationIsTravelOverSpeed() {
        // 30 pts/s scroll speed × 60-pt travel = 2s linear animation.
        let anim = MotionConstants.marqueeScroll(travelPoints: 60)
        #expect(anim == .linear(duration: 2.0))
    }

    @Test func marqueeScroll_zeroTravelClampsToZero() {
        // Guard the max(0,...) in the builder — negative travel from layout
        // race conditions should never produce a negative duration.
        let anim = MotionConstants.marqueeScroll(travelPoints: -10)
        #expect(anim == .linear(duration: 0.0))
    }
}
