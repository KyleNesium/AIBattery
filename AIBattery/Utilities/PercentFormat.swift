import Foundation

/// The one rule for turning a percentage into on-screen text.
///
/// **Truncating**: "100%" is shown only when the value really is ≥ 100, so a window at
/// 99.6% never reads as full beside a "Limit reached" that has not fired. Every surface
/// — detail bars, overview cards, the menu bar, tooltips, accessibility values — goes
/// through here so one reading cannot show two different numbers (the card and menu
/// bar used to round while the detail bar truncated: "100%" vs "99%").
enum PercentFormat {
    /// The whole-percent integer the display is built from: truncated, never negative,
    /// 0 for a non-finite input (`Int(_:)` traps on NaN / infinity).
    ///
    /// Snapped to a millionth first: percents arrive as `utilization * 100`, and
    /// `0.57 * 100` is `56.99999999999999` in binary floating point — a bare truncation
    /// would show 56% for a 57% reading. Nothing the app displays carries more than a
    /// few decimals, so the snap only ever removes float noise.
    static func whole(_ percent: Double) -> Int {
        guard percent.isFinite else { return 0 }
        let snapped = (percent * 1_000_000).rounded() / 1_000_000
        return max(0, Int(snapped))
    }

    /// `"42%"` — the bare number with a percent sign.
    static func display(_ percent: Double) -> String {
        "\(whole(percent))%"
    }

    /// `"58 percent"` — the spoken form for accessibility labels and values.
    static func spoken(_ percent: Double) -> String {
        "\(whole(percent)) percent"
    }

    /// Whole percent left before 100, consistent with `display`: a bar shown as "99%"
    /// reports 1 percent remaining, never 0.
    static func remaining(_ percent: Double) -> Int {
        max(0, 100 - whole(percent))
    }
}
