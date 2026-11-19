import AppKit
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

    /// The turn is one strand of the knot, a sixth of a revolution: a whole one read as
    /// the mark spinning. It has to stay a multiple of the mark's symmetry, or the mark
    /// rests rotated once the hover ends, because nothing unwinds it.
    @Test func theTurnIsOneStrandOfTheKnot() {
        #expect(ProviderBadge.hoverRotationDegrees == 60)
        #expect(ProviderBadge.hoverRotationDegrees.truncatingRemainder(dividingBy: ProviderBadge.markSymmetryDegrees) == 0)
    }

    /// A 60° turn only ends where it started because the bundled OpenAI mark looks the
    /// same every 60°. A replacement logo without that symmetry would rest crooked after
    /// every hover, so this renders the real resource, turned about its centre as
    /// `rotationEffect` turns it. The 30° turn is the control: the comparison must be able
    /// to fail. At 128 px a 60° turn differs by about 6% of the ink (anti-aliasing), 30°
    /// by over 100%; Claude's sunburst differs by 78% at 60°.
    @Test func theOpenAIMarkLooksTheSameAfterOneTurn() throws {
        let image = try #require(AIProvider.codex.markImage)
        let rest = Self.alpha(of: image, turnedBy: 0)
        let ink = Double(rest.reduce(0) { $0 + Int($1) })
        try #require(ink > 0)
        func difference(turnedBy degrees: Double) -> Double {
            let turned = Self.alpha(of: image, turnedBy: degrees)
            return Double(zip(rest, turned).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }) / ink
        }
        #expect(difference(turnedBy: ProviderBadge.hoverRotationDegrees) < 0.2)
        #expect(difference(turnedBy: 30) > 0.5)
    }

    /// The mark's alpha channel, drawn into a square bitmap turned about its centre.
    private static func alpha(of image: NSImage, turnedBy degrees: Double, side: Int = 128) -> [UInt8] {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: side * 4, bitsPerPixel: 32
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return [] }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let centre = CGFloat(side) / 2
        let turn = NSAffineTransform()
        turn.translateX(by: centre, yBy: centre)
        turn.rotate(byDegrees: degrees)
        turn.translateX(by: -centre, yBy: -centre)
        turn.concat()
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        guard let pixels = rep.bitmapData else { return [] }
        return (0..<side * side).map { pixels[$0 * 4 + 3] }
    }

    /// The mark's turn is an ornament, not feedback, so it must stay slower than the
    /// refresh button's spin — which *is* feedback and should feel immediate.
    @Test func theMarkTurnsSlowerThanTheRefreshButtonSpins() {
        #expect(MotionConstants.markSpin != MotionConstants.spin)
        #expect(MotionConstants.markSpin == .easeInOut(duration: 1.6))
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
