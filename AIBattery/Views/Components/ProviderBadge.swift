import SwiftUI

/// How a brand mark reacts to hover. The two marks are different shapes and a single
/// gesture flattered only one of them, so each gets the motion its own form implies.
enum MarkHoverMotion {
    /// Claude's sunburst: it flares. The mark swells while its coloured glow surges
    /// outward and then calms to a steady halo — a star putting out light, which is the
    /// one thing a starburst is drawing.
    ///
    /// Two earlier attempts are worth not repeating. Turning it read as a *wobble*: the
    /// rays are uneven, so a rotation has no symmetry to trace. Expanding a ghost copy of
    /// the mark read as a *smudge*: the ghost sits behind an opaque logo, so it is hidden
    /// for most of its travel and what escapes is a faint second starburst peeking
    /// between the real rays. Light has neither problem — it is not a shape, so it cannot
    /// double the logo, and it radiates whatever the mark's symmetry happens to be.
    case bloom
    /// OpenAI's knot: a single woven loop with no ends, so turning it traces the form
    /// instead of fighting it.
    case turn
}

extension AIProvider {
    /// The hover gesture this provider's mark gets. See `MarkHoverMotion`.
    var markHoverMotion: MarkHoverMotion {
        switch self {
        case .claude: .bloom
        case .codex: .turn
        }
    }
}

/// The provider's real brand mark, drawn bare in the provider's colour
/// (`AIProvider.markImage`, bundled SVG) — no filled tile. The tinted square was the
/// one saturated block in an otherwise monochrome header and made the chip read as a
/// foreign control; a logo-style mark reads as part of the title. The name always sits
/// next to it, so the tint is a recognition aid, never the only signal.
///
/// **Hover.** The mark lifts and glows, and then does whatever its shape asks for —
/// `AIProvider.markHoverMotion`. Claude blooms, Codex turns.
///
/// The turn is a *full* 360°, which matters: it lands on the exact pixels it started
/// from, so the mark can never settle visibly rotated the way a partial turn would.
/// Rotation resets without animation before each turn (the `RefreshButton` idiom) so the
/// angle never accumulates unbounded while always moving forward.
///
/// The bloom's ghost rests *expanded and invisible* (`bloom == 1`) and is snapped back to
/// the mark's own size before each pulse. Resting at the end of the animation rather than
/// the start is what lets one value drive both scale and fade with no gating flag and no
/// timer — at rest it is simply transparent.
///
/// `isHovered` lets a parent drive the animation from a **larger** target than the 12pt
/// mark itself: an overview card animates its logo when the whole card is hovered, which
/// is what makes the effect discoverable. Passing `nil` (the default) makes the badge
/// track its own hover, which is right where it stands alone, as in a Settings row.
///
/// Respects Reduce Motion: the mark neither moves nor scales, and only the glow
/// cross-fades, so the hover is still legible without movement.
struct ProviderBadge: View {
    let provider: AIProvider
    /// Externally driven hover, or `nil` to track the mark's own.
    var isHovered: Bool?
    /// Drawn size of the mark inside the fixed `providerBadgeSize` slot. Overview cards
    /// pass a larger one; the slot stays put so every text column still lines up.
    var markSize: CGFloat

    /// A whole revolution, and it must stay one. Nothing unwinds the angle when the
    /// hover ends, so any other value would leave the mark resting visibly rotated.
    static let hoverRotationDegrees: Double = 360

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selfHovered = false
    @State private var rotation: Double = 0
    /// Drives the flare, as a position along it rather than its brightness. Brightness is
    /// `sin(flare · π)`, which is 0 at both ends and 1 in the middle — so one monotonic
    /// animation both surges and decays, with no timer, no delayed second animation and
    /// no completion handler (macOS 13 has none). It rests at 1 and is snapped to 0
    /// before each flare; both ends are dark, so the reset can never show a jump.
    @State private var flare: Double = 1

    init(provider: AIProvider, isHovered: Bool? = nil, markSize: CGFloat = Layout.providerMarkSize) {
        self.provider = provider
        self.isHovered = isHovered
        self.markSize = markSize
    }

    private var hovered: Bool { isHovered ?? selfHovered }
    private var tint: Color { ThemeColors.providerBadge(provider) }
    private var motion: MarkHoverMotion { provider.markHoverMotion }

    /// How far the mark itself lifts. The bloom leans on scale for its whole effect, so
    /// it swells further than the turn, which carries the movement in the rotation.
    private var liftScale: CGFloat {
        switch motion {
        case .bloom: Layout.markBloomScale
        case .turn: Layout.markHoverScale
        }
    }

    /// Brightness at a position along the flare curve, 0…1 — dark at both ends, brightest
    /// in the middle. This shape is the whole trick: it turns one monotonic animation
    /// into a surge *and* a decay, and it makes the unanimated reset invisible because
    /// both ends of the sweep are dark.
    nonisolated static func flareIntensity(at position: Double) -> Double {
        sin(position * .pi)
    }

    /// How bright the flare is right now. Zero unless this mark blooms and is hovered.
    private var flareIntensity: Double {
        guard motion == .bloom, !reduceMotion, hovered else { return 0 }
        return Self.flareIntensity(at: flare)
    }

    var body: some View {
        mark
            .foregroundStyle(tint)
            // The glow is the part that survives Reduce Motion — a soft bloom in the
            // provider's own colour, so the mark looks lit from within rather than
            // outlined. Radius, not opacity alone: a flat halo reads as a selection ring.
            // A blooming mark adds its flare on top of this steady halo and decays back
            // onto it, so the hover never ends darker than it settles.
            .shadow(
                color: tint.opacity(
                    hovered ? ThemeColors.markGlowOpacity + flareIntensity * ThemeColors.markFlareOpacityBoost : 0
                ),
                radius: hovered ? Layout.markGlowRadius + flareIntensity * Layout.markFlareRadius : 0
            )
            .scaleEffect(hovered && !reduceMotion ? liftScale : 1)
            .rotationEffect(.degrees(reduceMotion ? 0 : rotation))
            .frame(width: Layout.providerBadgeSize, height: Layout.providerBadgeSize)
            .animation(MotionConstants.markLift(reduceMotion: reduceMotion), value: hovered)
            .onChange(of: hovered) { isHovering in
                guard isHovering, !reduceMotion else { return }
                switch motion {
                case .bloom: bloomOnce()
                case .turn: spinOnce()
                }
            }
            // Only bind a tracking area when nobody else is driving the state.
            .onHover {
                if isHovered == nil {
                    selfHovered = $0
                }
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder private var mark: some View {
        if let image = provider.markImage {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: markSize, height: markSize)
        } else {
            // Resource-missing fallback, scaled off `markSize` so a card's larger mark
            // does not silently drop back to the chip's size. Smaller than the mark it
            // stands in for, not equal: an SF Symbol carries internal padding the
            // bundled SVGs do not, so matching the sizes draws a visibly bigger glyph.
            Image(systemName: provider.symbolName)
                .font(.system(size: markSize * Layout.fallbackSymbolRatio, weight: .bold))
        }
    }

    /// One forward turn. Reset is deliberately unanimated so the angle returns to 0
    /// without visibly unwinding, then the turn animates to a full revolution.
    private func spinOnce() {
        withAnimation(.none) { rotation = 0 }
        withAnimation(MotionConstants.markSpin) { rotation = Self.hoverRotationDegrees }
    }

    /// One surge of light. Snapped to the dark end of the curve, then run through it —
    /// `flareIntensity` turns that single sweep into a rise and a decay.
    private func bloomOnce() {
        withAnimation(.none) { flare = 0 }
        withAnimation(MotionConstants.markBloom) { flare = 1 }
    }
}
