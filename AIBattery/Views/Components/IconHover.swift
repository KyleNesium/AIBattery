import SwiftUI

/// How an icon moves while the pointer is over its control: the motion half of a hover,
/// next to the colour change every control already makes.
///
/// Cheap by construction. Every preset is a rotation, a scale or an offset, which SwiftUI
/// applies after layout, so the icon's frame never changes: a hover never invalidates the
/// hosting view's intrinsic size and never makes the panel refit (see
/// `TransparentHostingView`). Nothing repeats either. There is one short spring on enter
/// and one on exit, and no cost while the pointer rests.
///
/// Respects Reduce Motion: the colour change stays and the movement is dropped (same rule
/// as `LiveDot` and `UpdateArrowButton`).
struct IconHover: Equatable {
    var rotationDegrees: Double = 0
    var scale: CGFloat = 1
    var offset: CGSize = .zero

    /// At rest, and always under Reduce Motion.
    static let identity = IconHover()

    /// One eighth of a turn clockwise. `gearshape` has eight teeth, so the gear advances
    /// exactly one tooth and settles on its own silhouette; the refresh arrows wind
    /// forward the way they spin on click.
    static let turn = IconHover(rotationDegrees: 45)

    /// A small swell for icons that don't point anywhere (footer and sort icons).
    static let pop = IconHover(scale: 1.15)

    /// Toward where an external link leads (`arrow.up.right`).
    static let outward = IconHover(offset: CGSize(width: 1.5, height: -1.5))

    /// Toward the menu that drops below the header chip (`chevron.down`).
    static let drop = IconHover(offset: CGSize(width: 0, height: 1.5))

    /// The update arrow lifts the way it points (`arrow.up.circle`).
    static let rise = IconHover(offset: CGSize(width: 0, height: -1.5))

    /// Along a disclosure chevron's own axis. Applied inside the collapse rotation, so it
    /// follows the glyph: rightward while collapsed, downward once expanded.
    static let forward = IconHover(offset: CGSize(width: 1.5, height: 0))

    /// What to draw now: the preset while active, nothing otherwise or under Reduce Motion.
    func resolved(active: Bool, reduceMotion: Bool) -> IconHover {
        active && !reduceMotion ? self : .identity
    }
}

private struct IconHoverModifier: ViewModifier {
    let effect: IconHover
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let current = effect.resolved(active: active, reduceMotion: reduceMotion)
        content
            .rotationEffect(.degrees(current.rotationDegrees))
            .scaleEffect(current.scale)
            .offset(current.offset)
            // Scoped to the icon and keyed on its own resolved state, so the spring stays
            // on this glyph and never reaches the rest of the control.
            .animation(MotionConstants.iconHover, value: current)
    }
}

extension View {
    /// Moves this icon by `effect` while `active`, which is normally the control's hover state.
    func iconHover(_ effect: IconHover, active: Bool) -> some View {
        modifier(IconHoverModifier(effect: effect, active: active))
    }
}
