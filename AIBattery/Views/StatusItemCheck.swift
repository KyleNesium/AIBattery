import AppKit

/// The menu bar item's identity, and a check, once after launch, that it reached the screen.
///
/// Why this exists: on macOS 27 users report menu bar apps whose process runs but whose icon
/// never appears. macOS 27 draws the whole menu bar as one window and keeps each item's place
/// by its autosave name; an item created without one is the implicit "Item-0". Other menu bar
/// apps hit by this (CodexBar, FineTune) moved to a stable name set at zero width, before the
/// item is sized. No fix is confirmed anywhere, so the app also writes one log line saying
/// whether the item made it onto the screen, which is the evidence a report needs.
enum StatusItemCheck {
    /// Stable identity for the status item. AppKit stores its position under
    /// `NSStatusItem Preferred Position <name>` in the app's defaults.
    static let autosaveName = "AIBatteryStatusItem"

    /// How long after launch to look. Long enough for the menu bar host to place the item.
    static let delay: TimeInterval = 10

    /// What AppKit reports about the item. Plain values, so the decision is testable.
    struct Observation: Equatable {
        var isVisible: Bool
        var hasWindow: Bool
        var buttonWidth: CGFloat
        var windowSize: CGSize
        var hasScreen: Bool
        var occlusionVisible: Bool

        var summary: String {
            "isVisible=\(isVisible) window=\(hasWindow) button=\(Int(buttonWidth)) "
                + "frame=\(Int(windowSize.width))x\(Int(windowSize.height)) screen=\(hasScreen) occlusionVisible=\(occlusionVisible)"
        }
    }

    /// Why the item looks hidden, or nil when it looks fine. "Looks": the system draws the
    /// item from its own process, so an in-process reading is a clue, not proof. It goes in
    /// the log for a person to read; the app acts on none of it.
    static func problem(with observation: Observation) -> String? {
        if !observation.isVisible {
            return "isVisible is false"
        }
        if !observation.hasWindow {
            return "the button has no window"
        }
        if observation.buttonWidth <= 0 || observation.windowSize.width <= 0 || observation.windowSize.height <= 0 {
            return "it has no size"
        }
        if !observation.hasScreen {
            return "its window is on no screen"
        }
        // `occlusionVisible` is logged but decides nothing. Since macOS 26 the item on
        // screen is drawn by Control Center: on macOS 26.5 every on-screen menu bar item
        // window belonged to Control Center and none to the apps that own the items, so an
        // app's own status window reads "not visible" whether or not its item is shown.
        // Nothing an app can read in-process tells it that the system has put its item
        // behind the notch or the overflow arrow.
        return nil
    }

    @MainActor
    static func observe(_ item: NSStatusItem) -> Observation {
        let window = item.button?.window
        return Observation(
            isVisible: item.isVisible,
            hasWindow: window != nil,
            buttonWidth: item.button?.frame.width ?? 0,
            windowSize: window?.frame.size ?? .zero,
            hasScreen: window?.screen != nil,
            occlusionVisible: window?.occlusionState.contains(.visible) ?? false
        )
    }

    /// Writes one line to the unified log. A hidden item is logged as an error so that
    /// `log show` still has it later; info lines are not kept.
    @MainActor
    static func log(_ item: NSStatusItem) {
        let observation = observe(item)
        let system = ProcessInfo.processInfo.operatingSystemVersionString
        if let problem = problem(with: observation) {
            AppLogger.general.error("Menu bar item looks hidden: \(problem, privacy: .public). \(observation.summary, privacy: .public), \(system, privacy: .public)")
        } else {
            AppLogger.general.info("Menu bar item is on screen. \(observation.summary, privacy: .public), \(system, privacy: .public)")
        }
    }
}
