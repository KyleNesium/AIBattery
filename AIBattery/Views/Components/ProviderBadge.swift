import SwiftUI

/// How a brand mark reacts to hover. The two marks are different shapes and a single
/// gesture flattered only one of them, so each gets the motion its own form implies.
enum MarkHoverMotion {
    /// Claude's sunburst: it springs. The mark sails well past the size it is heading
    /// for, snaps back under it, and wobbles onto it — rubbery rather than smooth.
    ///
    /// Three earlier attempts are worth not repeating. Turning it read as a *wobble*:
    /// the rays are uneven, so a rotation has no symmetry to trace. Expanding a ghost
    /// copy read as a *smudge*: behind an opaque logo the ghost is hidden for most of its
    /// travel, and what escapes is a faint second starburst between the real rays.
    ///
    /// The third failure is the instructive one. A hand-shaped curve — scale as some
    /// `f(position)` with `position` animated 0→1 — **does not play at all**. SwiftUI
    /// interpolates a modifier's value between its old and new state; it does not
    /// re-evaluate `body` per frame. Only `f(0)` and `f(1)` are ever sampled, so a curve
    /// that returns to its start value, as a pulse must, animates from one number to the
    /// identical number: nothing moves. Rubberiness has to come from the animation's own
    /// physics, which is why this case is simply an under-damped spring.
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
/// `AIProvider.markHoverMotion`. Claude springs, Codex turns.
///
/// The turn is a *full* 360°, which matters: it lands on the exact pixels it started
/// from, so the mark can never settle visibly rotated the way a partial turn would.
/// Rotation resets without animation before each turn (the `RefreshButton` idiom) so the
/// angle never accumulates unbounded while always moving forward.
///
/// The spring is the bloom's entire gesture — there is no second state to drive, and
/// deliberately so. SwiftUI interpolates a modifier's value between states rather than
/// re-running `body` per frame, so a hand-shaped curve read from `@State` only ever
/// samples its endpoints; see `MarkHoverMotion.bloom` for the version of this that
/// silently did nothing. Rubberiness lives in `MotionConstants.markLift`'s damping.
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

    /// Where the mark sits while hovered. The *path* it takes to get here is the spring's
    /// business, not this property's — see `MotionConstants.markLift`.
    private var currentScale: CGFloat {
        hovered && !reduceMotion ? liftScale : 1
    }

    var body: some View {
        mark
            .foregroundStyle(tint)
            // The glow is the part that survives Reduce Motion — a soft bloom in the
            // provider's own colour, so the mark looks lit from within rather than
            // outlined. Radius, not opacity alone: a flat halo reads as a selection ring.
            // It rides the same spring as the scale, so on a blooming mark the halo
            // overshoots with the logo instead of fading in flatly behind it.
            .shadow(
                color: tint.opacity(hovered ? ThemeColors.markGlowOpacity : 0),
                radius: hovered ? Layout.markGlowRadius : 0
            )
            .scaleEffect(currentScale)
            .rotationEffect(.degrees(reduceMotion ? 0 : rotation))
            .frame(width: Layout.providerBadgeSize, height: Layout.providerBadgeSize)
            .animation(MotionConstants.markLift(reduceMotion: reduceMotion, motion: motion), value: hovered)
            .onChange(of: hovered) { isHovering in
                guard isHovering, !reduceMotion, motion == .turn else { return }
                spinOnce()
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
}
