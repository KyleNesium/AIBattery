import AppKit

/// A check, once after launch, that the menu bar item reached the screen.
///
/// Why this exists: "AI Battery is running but not in my menu bar" is the report menu bar
/// apps get on macOS 27, which draws the whole menu bar as one window and hides items that
/// don't fit behind an arrow at its right end. Usually that is where the icon is. When it
/// is not, this line in the log is the evidence a report needs (`docs/FAQ.md` has the
/// command that collects it), and CI prints it from every launch, including on macOS 27.
enum StatusItemCheck {
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
