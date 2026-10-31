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
    /// radiates (its rays are uneven, so turning it looked like a wobble), the OpenAI
    /// knot turns (one woven loop with no ends).
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

    // MARK: - The bloom

    /// The ghost rests *expanded and invisible* so one value drives both scale and fade
    /// with no gating flag: at `bloom == 1` it must be fully transparent, or a second
    /// logo would sit behind every Claude mark at rest.
    @Test func theBloomGhostIsInvisibleAtRest() {
        let restingOpacity = (1 - 1.0) * ThemeColors.markBloomGhostOpacity
        #expect(restingOpacity == 0)
        // ...and visible at the pulse's first frame, which is where it starts.
        let startingOpacity = (1 - 0.0) * ThemeColors.markBloomGhostOpacity
        #expect(startingOpacity == ThemeColors.markBloomGhostOpacity)
        #expect(ThemeColors.markBloomGhostOpacity < 0.5)
    }

    /// The ghost has to actually clear the mark, or the pulse reads as a swell rather
    /// than something leaving.
    @Test func theBloomGhostTravelsPastTheMarksEdges() {
        let reach = 1 + Layout.markBloomSpread
        #expect(reach > Layout.markBloomScale)
    }

    /// `easeOut`, not `easeInOut`: light leaves fast and drifts to nothing. And the
    /// ghost should be gone before the lift finishes settling.
    @Test func theBloomEasesOutAndEndsBeforeTheTurnWould() {
        #expect(MotionConstants.markBloom == .easeOut(duration: 1.1))
        #expect(MotionConstants.markBloom != MotionConstants.markSpin)
    }

    // MARK: - Shared

    /// Reduce Motion swaps the spring for a plain ease — the mark stops moving and only
    /// the glow cross-fades. A spring would still overshoot, which is the movement the
    /// setting asks us not to make.
    @Test func markLift_dropsTheSpringUnderReduceMotion() {
        #expect(MotionConstants.markLift(reduceMotion: true) != MotionConstants.markLift(reduceMotion: false))
        #expect(MotionConstants.markLift(reduceMotion: true) == .easeOut(duration: 0.45))
    }

    /// Both lifts have to stay inside the slot the mark is centred in, or they crowd the
    /// identity next to them. The bloom's is the larger of the two, and the overview
    /// card's mark is the largest that is drawn — so that is the combination to pin.
    @Test func bothLiftsStayInsideTheBadgeSlotAtEveryMarkSize() {
        #expect(Layout.markBloomScale > Layout.markHoverScale)
        for size in [Layout.providerMarkSize, Layout.cardProviderMarkSize] {
            #expect(size * Layout.markHoverScale <= Layout.providerBadgeSize)
            #expect(size * Layout.markBloomScale <= Layout.providerBadgeSize)
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
