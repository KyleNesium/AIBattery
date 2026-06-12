import SwiftUI
import AppKit
import os.signpost

// MARK: - Panel toggle

extension StatusBarManager {
    @objc func statusItemClicked() {
        let now = Date()
        guard now.timeIntervalSince(lastClickAt) > 0.1 else { return }
        lastClickAt = now
        guard let panel, let button = statusItem?.button else { return }

        // Resume from idle suspension when user clicks the menu bar icon.
        // Global event monitors may not fire without Accessibility permission,
        // so this direct interaction is the reliable resume path.
        if let vm = viewModel, vm.isSuspended {
            vm.resumeFromUserInteraction()
        }

        let action = toggleState.toggle()
        switch action {
        case .hide:
            panel.orderOut(nil)
        case .show:
            // Refit panel to current SwiftUI content size — settings may have
            // collapsed while the panel was hidden, leaving a stale frame.
            if let hosting = hostingView {
                let screenMaxHeight = panel.screen?.visibleFrame.height ?? 900
                let maxPanelHeight = screenMaxHeight - 40
                let fittingHeight = min(max(hosting.fittingSize.height, Layout.panelMinHeight), maxPanelHeight)
                let fittingWidth = max(hosting.fittingSize.width, Layout.popoverWidth)
                panel.setContentSize(NSSize(width: fittingWidth, height: fittingHeight))
            }
            positionPanel(relativeTo: button)
            os_signpost(.begin, log: panelShowLog, name: "PanelShow")
            panel.orderFrontRegardless()
            panel.makeKey()
            os_signpost(.end, log: panelShowLog, name: "PanelShow")
        }
    }

    /// The status button's bounds converted to screen coordinates, or nil when
    /// the button isn't attached to a window. Shared by `positionPanel` and
    /// `currentTopAnchor` (previously duplicated in both).
    private func buttonScreenRect(for button: NSStatusBarButton) -> NSRect? {
        guard let buttonWindow = button.window else { return nil }
        let buttonRect = button.convert(button.bounds, to: nil)
        return buttonWindow.convertToScreen(buttonRect)
    }

    private func positionPanel(relativeTo button: NSStatusBarButton) {
        guard let panel, let screenRect = buttonScreenRect(for: button) else { return }

        let panelWidth = panel.frame.width
        let panelHeight = panel.frame.height
        let margin = Self.panelMargin

        // Prefer left-align to status item; flip to right-align if panel would overflow
        var x: CGFloat
        if let screen = (button.window?.screen ?? NSScreen.main)?.visibleFrame {
            let leftAligned = screenRect.minX
            let rightAligned = screenRect.maxX - panelWidth

            if leftAligned + panelWidth + margin > screen.maxX {
                // Near right edge — right-align to the status item
                x = max(screen.minX + margin, rightAligned)
            } else {
                // Normal — left-align to the status item
                x = max(screen.minX + margin, leftAligned)
            }
        } else {
            x = screenRect.minX
        }

        let y = screenRect.minY - panelHeight - margin

        // Store absolute top anchor so the resize observer can keep top pinned
        panelTopY = screenRect.minY - margin

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// Returns the panel's ideal top Y coordinate derived from the status button's
    /// current screen position. Nil if the button is not attached to a window.
    func currentTopAnchor() -> CGFloat? {
        guard let button = statusItem?.button,
              let screenRect = buttonScreenRect(for: button) else {
            return nil
        }
        return screenRect.minY - Self.panelMargin
    }
}

// MARK: - Panel subclass

/// Borderless panel that can become key (accepts keyboard events).
/// `hidesOnDeactivate` must return false — LSUIElement menu bar apps don't maintain
/// proper activation state, so the panel would auto-hide immediately after showing.
/// Manual click-outside + deactivation observers handle dismissal instead.
/// `onDismiss` is called for every orderOut path, including system-initiated ones,
/// ensuring toggleState never desyncs.
final class PopoverPanel: NSPanel {
    var onDismiss: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var hidesOnDeactivate: Bool {
        get { false }
        set { /* ignore — manual dismiss via observers */ }
    }

    override func orderOut(_ sender: Any?) {
        super.orderOut(sender)
        onDismiss?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            orderOut(nil)
        } else if event.keyCode == 12 && event.modifierFlags.contains(.command) { // Cmd+Q
            NSApplication.shared.terminate(nil)
        } else if !event.modifierFlags.contains(.command) {
            // Forward unmodified keys to SwiftUI via notification
            switch event.charactersIgnoringModifiers {
            case "1", "2", "3", "r":
                NotificationCenter.default.post(
                    name: .panelKeyPress,
                    object: event.charactersIgnoringModifiers
                )
            default:
                // Arrow keys: keyCode 123 = left, 124 = right
                if event.keyCode == 123 || event.keyCode == 124 {
                    NotificationCenter.default.post(
                        name: .panelKeyPress,
                        object: event.keyCode == 123 ? "left" : "right"
                    )
                } else {
                    super.keyDown(with: event)
                }
            }
        } else {
            super.keyDown(with: event)
        }
    }
}

// MARK: - SwiftUI content

/// Wrapper view that switches between authenticated and unauthenticated states.
struct PopoverContentView: View {
    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject var oauthManager: OAuthManager

    var body: some View {
        Group {
            if oauthManager.isAuthenticated {
                UsagePopoverView(viewModel: viewModel)
            } else {
                AuthView(oauthManager: oauthManager)
            }
        }
        .frame(width: Layout.popoverWidth)
        .background(ThemeColors.panelBackground)
    }
}

// MARK: - Transparent hosting view

/// NSHostingView subclass that suppresses the default opaque background fill,
/// allowing the SwiftUI-level background to control the panel's appearance.
final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        // Skip super — the default implementation fills with the window background color.
        // SwiftUI content renders via the layer pipeline, not draw(), so this is safe.
    }
}
