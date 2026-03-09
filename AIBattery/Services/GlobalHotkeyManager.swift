import AppKit

/// System-wide keyboard shortcut manager for toggling the popover.
/// Uses `NSEvent` monitors — global for when another app is active, local for when AI Battery is active.
@MainActor
public final class GlobalHotkeyManager {
    // nonisolated(unsafe) so deinit can read them for cleanup
    nonisolated(unsafe) private var globalMonitor: Any?
    nonisolated(unsafe) private var localMonitor: Any?
    private var onToggle: (() -> Void)?

    // Default hotkey: Option+Shift+B
    static let defaultKeyCode: UInt16 = 11  // "B" key
    static let defaultModifiers: NSEvent.ModifierFlags = [.option, .shift]

    /// Extracted pure function: does this key event match the hotkey combo?
    nonisolated static func matches(event: NSEvent, keyCode: UInt16 = defaultKeyCode, modifiers: NSEvent.ModifierFlags = defaultModifiers) -> Bool {
        guard event.keyCode == keyCode else { return false }
        // Mask to only device-independent modifier flags (ignore caps lock, function, etc.)
        let eventMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return eventMods == modifiers
    }

    /// Start monitoring for the global hotkey.
    /// - Parameter onToggle: Called on the main actor when the hotkey is pressed.
    func start(onToggle: @escaping () -> Void) {
        self.onToggle = onToggle
        stop()

        // Global monitor: fires when another app is in the foreground
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Self.matches(event: event) else { return }
            Task { @MainActor in
                self?.onToggle?()
            }
        }

        // Local monitor: fires when AI Battery is the active app
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Self.matches(event: event) else { return event }
            Task { @MainActor in
                self?.onToggle?()
            }
            return nil  // consume the event
        }
    }

    func stop() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    deinit {
        if let monitor = globalMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localMonitor { NSEvent.removeMonitor(monitor) }
    }
}
