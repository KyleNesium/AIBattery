import SwiftUI
import Testing
@testable import AIBatteryCore

/// `@MainActor` + `.serialized`: the suite constructs SwiftUI views, and AppKit's
/// one-time init deadlocks when raced from the parallel pool.
@MainActor
@Suite("ProviderBadge", .serialized)
struct ProviderBadgeTests {
    // MARK: - Which gesture each mark gets

    /// The two marks are different shapes and get different gestures: Claude's sunburst
    /// springs (its rays are uneven, so turning it looked like a wobble), the OpenAI knot
    /// turns (one woven loop with no ends).
    @Test func eachMarkGetsTheGestureItsShapeImplies() {
        #expect(AIProvider.claude.markHoverMotion == .bloom)
        #expect(AIProvider.codex.markHoverMotion == .turn)
    }

    // MARK: - The turn

    /// The turn has to be a whole revolution. Any other angle leaves the mark resting
    /// rotated once the hover ends, because nothing unwinds it.
    @Test func theTurnIsAWholeRevolution() {
        #expect(ProviderBadge.hoverRotationDegrees == 360)
        #expect(ProviderBadge.hoverRotationDegrees.truncatingRemainder(dividingBy: 360) == 0)
    }

    /// The mark's turn is an ornament, not feedback, so it must stay slower than the
    /// refresh button's spin — which *is* feedback and should feel immediate.
    @Test func theMarkTurnsSlowerThanTheRefreshButtonSpins() {
        #expect(MotionConstants.markSpin != MotionConstants.spin)
        #expect(MotionConstants.markSpin == .easeInOut(duration: 1.3))
        #expect(MotionConstants.spin == .easeInOut(duration: 0.5))
    }

    // MARK: - Shared

    /// Reduce Motion swaps the spring for a plain ease — the mark stops moving and only
    /// the glow cross-fades. A spring would still overshoot, which is the movement the
    /// setting asks us not to make.
    @Test func markLift_dropsTheSpringUnderReduceMotion() {
        for motion in [MarkHoverMotion.bloom, .turn] {
            #expect(
                MotionConstants.markLift(reduceMotion: true, motion: motion)
                    != MotionConstants.markLift(reduceMotion: false, motion: motion)
            )
            #expect(MotionConstants.markLift(reduceMotion: true, motion: motion) == .easeOut(duration: 0.45))
        }
    }

    /// The rubberiness has to live in the spring, because SwiftUI interpolates a
    /// modifier's value between states rather than re-running `body` per frame — a
    /// hand-shaped curve read from state only ever samples its endpoints. So the bloom's
    /// spring must stay **under-damped** (bouncy) and distinctly bouncier than the turn's,
    /// which settles quietly beneath a rotation that is already carrying the movement.
    @Test func theBloomSpringIsUnderDampedAndBouncierThanTheTurns() {
        #expect(
            MotionConstants.markLift(reduceMotion: false, motion: .bloom)
                == .spring(response: 0.45, dampingFraction: 0.3)
        )
        #expect(
            MotionConstants.markLift(reduceMotion: false, motion: .turn)
                == .spring(response: 0.75, dampingFraction: 0.7)
        )
        #expect(
            MotionConstants.markLift(reduceMotion: false, motion: .bloom)
                != MotionConstants.markLift(reduceMotion: false, motion: .turn)
        )
    }

    /// A spring can only be as rubbery as the distance it covers, so the bloom needs
    /// visibly more travel than the turn — too small a target and the overshoot never
    /// registers, which is exactly how this read as "it just gets bigger".
    @Test func theBloomHasEnoughTravelForItsOvershootToRegister() {
        #expect(Layout.markBloomScale > Layout.markHoverScale)
        let bloomTravel = Layout.markBloomScale - 1
        let turnTravel = Layout.markHoverScale - 1
        #expect(bloomTravel > turnTravel * 1.5)
    }

    /// The turn's lift stays inside the slot the mark is centred in. The bloom's does
    /// not, and must not — constraining it to the slot is what left too little travel for
    /// the overshoot to read. What actually matters is that neither reaches the identity
    /// beside it, so the real bound is the gap between badge and name, not the slot.
    @Test func liftsNeverReachTheIdentityBesideThem() {
        for size in [Layout.providerMarkSize, Layout.cardProviderMarkSize] {
            #expect(size * Layout.markHoverScale <= Layout.providerBadgeSize)
            let widest = size * Layout.markBloomScale
            let overflowPerSide = max(0, (widest - Layout.providerBadgeSize) / 2)
            #expect(overflowPerSide < Layout.accountChipSpacing)
        }
    }

    /// The resource-missing fallback scales with the mark instead of sitting at a fixed
    /// size, or a card's larger mark would silently drop back to the chip's glyph. It
    /// stays smaller than the mark: SF Symbols carry padding the bundled SVGs do not.
    @Test func theFallbackSymbolTracksTheMarkSizeWithoutMatchingIt() {
        #expect(Layout.fallbackSymbolRatio < 1)
        #expect(Layout.providerMarkSize * Layout.fallbackSymbolRatio == 10)
        let onACard = Layout.cardProviderMarkSize * Layout.fallbackSymbolRatio
        #expect(onACard > Layout.providerMarkSize * Layout.fallbackSymbolRatio)
    }

    /// The overview card draws a bigger mark than the header chip — a card is a wider,
    /// quieter surface and at the chip's size the logo read as an afterthought. The
    /// slot does not change with it, so every text column still lines up.
    @Test func theOverviewCardDrawsALargerMarkThanTheChip() {
        #expect(Layout.cardProviderMarkSize > Layout.providerMarkSize)
        #expect(ProviderBadge(provider: .claude).markSize == Layout.providerMarkSize)
        #expect(
            ProviderBadge(provider: .claude, markSize: Layout.cardProviderMarkSize).markSize
                == Layout.cardProviderMarkSize
        )
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
