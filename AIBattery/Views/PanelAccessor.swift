import SwiftUI

/// Configures the underlying NSPanel created by MenuBarExtra to properly
/// capture mouse events, preventing hover/click pass-through to windows beneath.
public struct PanelAccessor: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> NSView {
        PanelConfigurationView()
    }

    public func updateNSView(_ nsView: NSView, context: Context) {}
}

private class PanelConfigurationView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let panel = window as? NSPanel else { return }
        panel.becomesKeyOnlyIfNeeded = false
        panel.acceptsMouseMovedEvents = true
    }
}
