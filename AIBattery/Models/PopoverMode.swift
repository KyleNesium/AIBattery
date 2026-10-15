import Foundation

/// Which face the popover shows: all accounts at once, or the active account's detail.
///
/// Decided once, on the first open after launch (`initial`), then **remembered** across
/// opens: drill into an account, click away, come back — you are still in that account,
/// and the back chevron is the only way to the overview. `next` keeps a remembered face
/// valid as accounts come and go. A single account never sees the overview.
enum PopoverMode: Equatable, Sendable {
    case overview
    case detail

    /// First open after launch: two or more eligible accounts land on the overview.
    static func initial(eligibleAccountCount: Int) -> PopoverMode {
        eligibleAccountCount >= 2 ? .overview : .detail
    }

    /// Every later open: keep where the user was, unless that face is no longer valid.
    static func onShow(remembered: PopoverMode?, eligibleAccountCount: Int) -> PopoverMode {
        guard let remembered else { return initial(eligibleAccountCount: eligibleAccountCount) }
        return next(current: remembered, eligibleAccountCount: eligibleAccountCount)
    }

    /// While the panel is open: losing accounts down to one leaves the overview (it has
    /// nothing left to compare), but gaining an account never yanks the user out of a
    /// detail view they chose — the next open lands on the overview instead.
    static func next(current: PopoverMode, eligibleAccountCount: Int) -> PopoverMode {
        if current == .overview, eligibleAccountCount < 2 {
            return .detail
        }
        return current
    }
}

/// What Escape does, given where the popover is. Pure so the panel's `keyDown` and the
/// SwiftUI root agree without either one guessing.
enum PopoverEscapeAction: Equatable, Sendable {
    case backToOverview
    case close
}

enum PopoverEscapeRouting {
    /// Escape in a detail view that has somewhere to go back to returns to the overview;
    /// everywhere else (overview, Settings open, single account) it closes the panel.
    static func consume(mode: PopoverMode, showSettings: Bool, showsBack: Bool) -> PopoverEscapeAction {
        (mode == .detail && !showSettings && showsBack) ? .backToOverview : .close
    }
}
