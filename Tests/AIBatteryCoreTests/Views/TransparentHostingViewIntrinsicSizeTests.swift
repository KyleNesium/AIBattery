import Testing
import SwiftUI
import AppKit
@testable import AIBatteryCore

/// The popover panel refits its height from `hosting.fittingSize`. That refit used to be
/// scheduled only from `NSView.frameDidChangeNotification`, i.e. only after AppKit's
/// window auto-layout had already resized the panel as a side effect. When the SwiftUI
/// tree changed size without that side effect (the Settings toggle, intermittently),
/// nothing re-read the fitting size and the panel kept its old height with the content
/// centred and clipped. `TransparentHostingView` now reports every intrinsic-size
/// invalidation directly, which is the cause rather than the side effect.
@MainActor
final class SizeToggle: ObservableObject {
    @Published var tall = false
}

struct SizeToggleView: View {
    @ObservedObject var toggle: SizeToggle

    var body: some View {
        VStack(spacing: 0) {
            Text("header").frame(height: 30)
            if toggle.tall {
                Text("tall").frame(height: 300).transition(.opacity)
            } else {
                Text("short").frame(height: 60)
            }
        }
        .frame(width: Layout.popoverWidth)
    }
}

@MainActor
@Suite("TransparentHostingView intrinsic-size hook", .serialized)
struct TransparentHostingViewIntrinsicSizeTests {
    private func pump(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    @Test func contentSizeChange_reportsIntrinsicSizeInvalidation() {
        _ = NSApplication.shared
        // Run AppKit's menu-system one-time initializer on the main thread NOW, before a
        // hosting view exists. The hosting view registers main-queue notification
        // observers; if an off-main test (`NSColor.system*` in a suite init) is the first
        // to hit that initializer, it posts a defaults notification and blocks on those
        // observers while the main thread waits on the same initializer — a deadlock
        // that hung the whole parallel suite.
        _ = NSImage(size: NSSize(width: 1, height: 1)).cgImage(forProposedRect: nil, context: nil, hints: nil)
        let toggle = SizeToggle()
        let hosting = TransparentHostingView(rootView: SizeToggleView(toggle: toggle))
        hosting.translatesAutoresizingMaskIntoConstraints = false

        let panel = PopoverPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.contentView = hosting
        panel.setContentSize(NSSize(width: Layout.popoverWidth, height: 90))
        panel.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        panel.orderFrontRegardless()
        pump(0.3)

        var invalidations = 0
        var lastFitting: CGFloat = 0
        hosting.onIntrinsicSizeInvalidated = {
            invalidations += 1
            lastFitting = hosting.fittingSize.height
        }

        withAnimation(MotionConstants.standard) { toggle.tall = true }
        pump(0.6)

        #expect(invalidations > 0)
        #expect(lastFitting == 330)
        #expect(hosting.fittingSize.height == 330)

        // Full teardown so the hosting view's observers don't outlive the test (see the
        // deadlock note above).
        hosting.onIntrinsicSizeInvalidated = nil
        panel.orderOut(nil)
        panel.contentView = nil
        panel.close()
        pump(0.1)
    }
}
