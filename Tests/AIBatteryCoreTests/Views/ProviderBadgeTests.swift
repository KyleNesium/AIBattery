import SwiftUI
import Testing
@testable import AIBatteryCore

/// `@MainActor` + `.serialized`: the suite constructs SwiftUI views, and AppKit's
/// one-time init deadlocks when raced from the parallel pool.
@MainActor
@Suite("ProviderBadge", .serialized)
struct ProviderBadgeTests {
    /// Reduce Motion swaps the spring for a plain ease — the mark stops moving and only
    /// the glow cross-fades. A spring would still overshoot, which is the movement the
    /// setting asks us not to make.
    @Test func markLift_dropsTheSpringUnderReduceMotion() {
        #expect(MotionConstants.markLift(reduceMotion: true) != MotionConstants.markLift(reduceMotion: false))
        #expect(MotionConstants.markLift(reduceMotion: true) == .easeOut(duration: 0.2))
    }

    /// The turn has to be a whole revolution. Any other angle leaves the mark resting
    /// rotated once the hover ends, because nothing unwinds it.
    @Test func theHoverTurnIsAWholeRevolution() {
        #expect(ProviderBadge.hoverRotationDegrees == 360)
        #expect(ProviderBadge.hoverRotationDegrees.truncatingRemainder(dividingBy: 360) == 0)
    }

    /// The lift has to stay inside the slot the mark is centred in, or it crowds the
    /// identity next to it.
    @Test func theLiftStaysInsideTheBadgeSlot() {
        let lifted = Layout.providerMarkSize * Layout.markHoverScale
        #expect(lifted <= Layout.providerBadgeSize)
    }

    /// The bloom is visible but never opaque — it sits behind a dense shape, not a
    /// thin glyph, so a full-strength halo would spill past the mark.
    @Test func theGlowIsVisibleButNotOpaque() {
        #expect(ThemeColors.markGlowOpacity > 0)
        #expect(ThemeColors.markGlowOpacity < 1)
        #expect(Layout.markGlowRadius > 0)
    }

    /// A badge with no external hover tracks its own; one given a value defers to it.
    @Test func externalHoverOverridesTheBadgesOwn() {
        #expect(ProviderBadge(provider: .claude).isHovered == nil)
        #expect(ProviderBadge(provider: .claude, isHovered: true).isHovered == true)
        #expect(ProviderBadge(provider: .codex, isHovered: false).isHovered == false)
    }
}
