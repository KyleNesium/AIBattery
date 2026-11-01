import SwiftUI

/// A `TimelineView(.periodic)` that only ticks while the popover panel is on screen.
///
/// The panel is hidden with `orderOut`, which does **not** fire `onDisappear` (the same
/// reason `DeferredRenderState` exists). A plain `TimelineView` therefore keeps waking
/// the main queue 24/7 — including while polling is idle-suspended, which is what stops
/// the process ever going quiet, and that is what the energy-impact metric measures.
///
/// While hidden the content is rendered once with the current date and left alone; the
/// next `.panelDidShow` re-arms the timeline and the content is recomputed on that same
/// evaluation, so nothing stale is ever on screen.
struct PanelPeriodicView<Content: View>: View {
    let interval: TimeInterval
    @ViewBuilder let content: (Date) -> Content

    @State private var isPanelVisible = true

    init(every interval: TimeInterval, @ViewBuilder content: @escaping (Date) -> Content) {
        self.interval = interval
        self.content = content
    }

    var body: some View {
        Group {
            if isPanelVisible {
                TimelineView(.periodic(from: .now, by: interval)) { context in
                    content(context.date)
                }
            } else {
                content(Date())
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .panelDidShow)) { _ in isPanelVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: .panelDidDismiss)) { _ in isPanelVisible = false }
    }
}
