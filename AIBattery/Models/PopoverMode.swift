import Foundation

/// Which face the popover shows: all accounts at once, or the active account's detail.
///
/// Decided on every panel open (`.panelDidShow`), never remembered across opens — with
/// two or more accounts the overview is always the landing page, and a single account
/// never sees it.
enum PopoverMode: Equatable, Sendable {
    case overview
    case detail

    /// On every panel open: two or more eligible accounts land on the overview.
    static func initial(eligibleAccountCount: Int) -> PopoverMode {
        eligibleAccountCount >= 2 ? .overview : .detail
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
