import SwiftUI

/// The provider's real brand mark, drawn bare in the provider's colour
/// (`AIProvider.markImage`, bundled SVG) — no filled tile. The tinted square was the
/// one saturated block in an otherwise monochrome header and made the chip read as a
/// foreign control; a logo-style mark reads as part of the title. The name always sits
/// next to it, so the tint is a recognition aid, never the only signal.
///
/// **Hover.** The mark turns once and lifts. Both brand marks are built around a centre
/// — Claude's is a sunburst, OpenAI's a knot — so rotation is the one gesture that suits
/// each without distorting it. The turn is a *full* 360°, which matters: it lands on the
/// exact pixels it started from, so the mark can never settle visibly rotated the way a
/// partial turn would. Rotation is reset without animation before each turn (the
/// `RefreshButton` idiom) so the angle never accumulates unbounded while always moving
/// forward.
///
/// `isHovered` lets a parent drive the animation from a **larger** target than the 12pt
/// mark itself: an overview card spins its logo when the whole card is hovered, which is
/// what makes the effect discoverable. Passing `nil` (the default) makes the badge track
/// its own hover, which is right where it stands alone, as in a Settings row.
///
/// Respects Reduce Motion: the mark neither turns nor springs, and only the glow
/// cross-fades, so the hover is still legible without movement.
struct ProviderBadge: View {
    let provider: AIProvider
    /// Externally driven hover, or `nil` to track the mark's own.
    var isHovered: Bool?

    /// A whole revolution, and it must stay one. Nothing unwinds the angle when the
    /// hover ends, so any other value would leave the mark resting visibly rotated.
    static let hoverRotationDegrees: Double = 360

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selfHovered = false
    @State private var rotation: Double = 0

    init(provider: AIProvider, isHovered: Bool? = nil) {
        self.provider = provider
        self.isHovered = isHovered
    }

    private var hovered: Bool { isHovered ?? selfHovered }

    var body: some View {
        mark
            .foregroundStyle(ThemeColors.providerBadge(provider))
            // The glow is the part that survives Reduce Motion — a soft bloom in the
            // provider's own colour, so the mark looks lit from within rather than
            // outlined. Radius, not opacity alone: a flat halo reads as a selection ring.
            .shadow(
                color: ThemeColors.providerBadge(provider).opacity(hovered ? ThemeColors.markGlowOpacity : 0),
                radius: hovered ? Layout.markGlowRadius : 0
            )
            .scaleEffect(hovered && !reduceMotion ? Layout.markHoverScale : 1)
            .rotationEffect(.degrees(reduceMotion ? 0 : rotation))
            .frame(width: Layout.providerBadgeSize, height: Layout.providerBadgeSize)
            .animation(MotionConstants.markLift(reduceMotion: reduceMotion), value: hovered)
            .onChange(of: hovered) { isHovering in
                guard isHovering, !reduceMotion else { return }
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
                .frame(width: Layout.providerMarkSize, height: Layout.providerMarkSize)
        } else {
            Image(systemName: provider.symbolName)
                .font(Typography.badgeSymbol)
        }
    }

    /// One forward turn. Reset is deliberately unanimated so the angle returns to 0
    /// without visibly unwinding, then the turn animates to a full 360°.
    private func spinOnce() {
        withAnimation(.none) { rotation = 0 }
        withAnimation(MotionConstants.markSpin) { rotation = Self.hoverRotationDegrees }
    }
}
