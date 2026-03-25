import SwiftUI
import AppKit
import Combine
import os.signpost

extension Notification.Name {
    /// Keyboard shortcut pressed in the popover panel — forwarded to SwiftUI views.
    static let panelKeyPress = Notification.Name("panelKeyPress")
    /// Panel was dismissed — used to reset transient popover UI state kept alive by NSHostingView reuse.
    static let panelDidDismiss = Notification.Name("panelDidDismiss")
}

// MARK: - Toggle State Machine

/// Pure value-type toggle state machine extracted from StatusBarManager for testability.
/// Covers RESP-03: every dismiss path sets isShowing to false.
struct PanelToggleState {
    private(set) var isShowing: Bool = false

    mutating func show() {
        isShowing = true
    }

    mutating func dismiss() {
        isShowing = false
    }

    /// Transitions the state and returns the action to perform.
    mutating func toggle() -> PanelAction {
        if isShowing {
            dismiss()
            return .hide
        } else {
            show()
            return .show
        }
    }

    enum PanelAction: Equatable {
        case show, hide
    }
}

// MARK: - StatusBarManager

/// Manages the NSStatusItem and a floating NSPanel directly, replacing SwiftUI's MenuBarExtra.
/// Uses a standalone NSPanel instead of NSPopover — immune to macOS auto-hide and focus changes.
/// The panel stays open until the user clicks the status item again or presses Escape.
@MainActor
public final class StatusBarManager: NSObject {
    private var statusItem: NSStatusItem?
    private var panel: PopoverPanel?
    private var hostingView: NSHostingView<PopoverContentView>?
    private var cancellables = Set<AnyCancellable>()
    private var escapeMonitor: Any?
    private var clickOutsideMonitor: Any?
    /// Toggle state machine — tracks intended panel visibility.
    /// All dismiss paths (including system-initiated orderOut) call toggleState.dismiss() via onDismiss callback.
    private var toggleState = PanelToggleState()
    private var deactivationObserver: Any?
    private let panelShowLog = OSLog(subsystem: "com.kylenesium.AIBattery", category: .pointsOfInterest)
    /// Timestamp of last click — debounces rapid clicks during toggle.
    private var lastClickAt: Date = .distantPast
    private var appearanceObserver: NSKeyValueObservation?
    private var frameObserver: Any?
    /// Absolute Y coordinate of the panel's top edge (just below the menu bar).
    /// Set by `positionPanel` and used by the resize observer to keep the top anchored.
    private var panelTopY: CGFloat = 0

    // Snapshot of current render state
    private var currentPercent: Double = 0
    private var currentColor: NSColor = .systemGreen
    private var currentIsThrottled: Bool = false
    /// Whether we've received at least one update (so we can detect real transitions vs initial state).
    private var hasReceivedFirstUpdate: Bool = false

    // Recovery sparkle: 30s celebration after throttle clears
    private var isSparkleActive: Bool = false
    private var sparkleTimer: Timer?
    /// Duration of the recovery sparkle effect after throttle clears.
    static let sparkleDuration: TimeInterval = 30

    public override init() {
        super.init()
    }

    public func setup(viewModel: UsageViewModel, oauthManager: OAuthManager) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Configure native AppKit button (no NSHostingView — doesn't render in NSStatusBarButton)
        if let button = item.button {
            button.image = MenuBarIcon.statusBarImage(for: 0, color: ThemeColors.barNSColor(percent: 0))
            // Text left, icon right — matches macOS battery layout
            button.imagePosition = .imageTrailing
            button.imageHugsTitle = true
            button.title = "..."
            // Match macOS battery percentage text: monospaced digits at menu bar size.
            button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            button.action = #selector(statusItemClicked)
            button.target = self
            button.setAccessibilityLabel("AI Battery")
        }

        // Floating panel — not NSPopover, so macOS can't auto-hide it
        let panel = PopoverPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .moveToActiveSpace]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .none

        // Follow system light/dark appearance so the popover material matches the OS theme
        panel.appearance = NSApp.effectiveAppearance

        // Wire onDismiss callback — consolidates all dismiss paths through a single point.
        // PopoverPanel.orderOut calls onDismiss for every path (including system-initiated ones),
        // making desync impossible. dismiss() is idempotent so double-calls are safe.
        panel.onDismiss = { [weak self] in
            self?.toggleState.dismiss()
            NotificationCenter.default.post(name: .panelDidDismiss, object: nil)
        }

        // SwiftUI content — background color is set in PopoverContentView
        // using the system's controlBackgroundColor which adapts to light/dark.
        let hosting = NSHostingView(
            rootView: PopoverContentView(viewModel: viewModel, oauthManager: oauthManager)
        )
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = 10
        hosting.layer?.masksToBounds = true

        panel.contentView = hosting
        panel.setContentSize(NSSize(width: Layout.popoverWidth, height: 700))

        // Resize panel when SwiftUI content changes height.
        // Max height is screen-relative so all sections fit on most displays.
        // Debounced: coalesces rapid layout changes into a single frame update.
        hosting.setContentHuggingPriority(.defaultHigh, for: .vertical)
        hosting.postsFrameChangedNotifications = true
        var resizeWorkItem: DispatchWorkItem?
        frameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: hosting,
            queue: .main
        ) { [weak panel, weak hosting, weak self] _ in
            resizeWorkItem?.cancel()
            let work = DispatchWorkItem {
                MainActor.assumeIsolated {
                    guard let panel, let hosting, let self else { return }
                    guard self.toggleState.isShowing else { return }
                    let screenMaxHeight = panel.screen?.visibleFrame.height ?? 900
                    let maxPanelHeight = screenMaxHeight - 40
                    let fittingHeight = min(hosting.fittingSize.height, maxPanelHeight)
                    let newHeight = max(fittingHeight, 100)
                    // Skip no-op frame updates to avoid layout feedback loops
                    guard abs(newHeight - panel.frame.height) > 0.5 else { return }
                    // Grow downward from fixed top anchor (set by positionPanel)
                    let newOrigin = NSPoint(
                        x: panel.frame.origin.x,
                        y: self.panelTopY - newHeight
                    )
                    let fittingWidth = max(hosting.fittingSize.width, Layout.popoverWidth)
                    panel.setFrame(
                        NSRect(origin: newOrigin, size: NSSize(width: fittingWidth, height: newHeight)),
                        display: true,
                        animate: false
                    )
                }
            }
            resizeWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.016, execute: work)
        }

        // React to snapshot or staleness changes — debounced to avoid rapid-fire redraws
        viewModel.$snapshot
            .combineLatest(viewModel.$lastFreshFetch)
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self, weak item, weak viewModel] _, _ in
                guard let self, let button = item?.button, let viewModel else { return }
                self.updateButton(button, viewModel: viewModel)
            }
            .store(in: &cancellables)

        // Refresh on auth change
        oauthManager.$isAuthenticated
            .removeDuplicates()
            .sink { authenticated in
                if authenticated {
                    Task { @MainActor in await viewModel.refresh() }
                }
            }
            .store(in: &cancellables)

        // Close panel on Escape key.
        // onDismiss fires from PopoverPanel.orderOut — no redundant dismiss() call needed.
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53, let self, self.toggleState.isShowing {
                self.panel?.orderOut(nil)
                return nil
            }
            return event
        }

        // Close panel when clicking outside (global mouse events from other apps).
        // Runs on main queue — no async Task needed.
        // onDismiss fires from PopoverPanel.orderOut — no redundant dismiss() call needed.
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.toggleState.isShowing else { return }
            // On LSUIElement apps, the status bar click also fires as a global event.
            // Check if the click landed on the status item — if so, statusItemClicked handles it.
            if let buttonWindow = self.statusItem?.button?.window {
                let screenPoint = event.window == nil
                    ? event.locationInWindow
                    : event.window!.convertPoint(toScreen: event.locationInWindow)
                if buttonWindow.frame.contains(screenPoint) { return }
            }
            // Ignore clicks on our own panel
            if let panel = self.panel, panel.frame.contains(NSEvent.mouseLocation) { return }
            self.panel?.orderOut(nil)
        }

        // Track system appearance changes so the panel follows light/dark mode
        appearanceObserver = NSApp.observe(\.effectiveAppearance) { [weak panel] _, _ in
            panel?.appearance = NSApp.effectiveAppearance
        }

        // Close panel when app loses focus (Cmd+Tab, click another app's window).
        // onDismiss fires from PopoverPanel.orderOut — no redundant dismiss() call needed.
        deactivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.toggleState.isShowing else { return }
            self.panel?.orderOut(nil)
        }

        self.statusItem = item
        self.panel = panel
        self.hostingView = hosting

        // Pre-warm: force SwiftUI's first layout pass now (at startup) so the first
        // user click doesn't pay the ~500ms+ layout cost. Show the panel offscreen
        // for one frame, then hide it.
        panel.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        panel.orderFrontRegardless()
        DispatchQueue.main.async {
            panel.orderOut(nil)
        }
    }

    deinit {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let observer = deactivationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let obs = frameObserver { NotificationCenter.default.removeObserver(obs) }
        appearanceObserver?.invalidate()
        sparkleTimer?.invalidate()
    }

    // MARK: - Button update

    private func updateButton(_ button: NSStatusBarButton, viewModel: UsageViewModel) {
        let metricMode = resolveMetricMode(viewModel: viewModel)
        let percent = viewModel.snapshot?.percent(for: metricMode) ?? 0
        let rateLimits = viewModel.snapshot?.rateLimits
        let isThrottled = rateLimits?.isThrottled ?? false
        // Show broken star when throttled OR any window hits 100%.
        let isExhausted = isThrottled
            || (rateLimits?.fiveHourPercent ?? 0) >= 100
            || (rateLimits?.sevenDayPercent ?? 0) >= 100
        let starColor = resolveStarColor(metricMode: metricMode, percent: percent, isThrottled: isExhausted)

        updateSparkleState(isThrottled: isExhausted)
        updateRenderState(percent: percent, color: starColor, isThrottled: isExhausted)

        button.image = MenuBarIcon.statusBarImage(
            for: percent,
            color: starColor,
            isBroken: isExhausted,
            isSparkle: isSparkleActive,
            pulseStep: 0
        )

        let displayText = resolveDisplayText(rateLimits: rateLimits, percent: percent)
        button.title = displayText
        button.setAccessibilityValue(displayText)
        // Never grey out — the icon always shows the last known state.
        // Other menu bar apps (Battery, WiFi) don't dim on stale data.
    }

    private func resolveMetricMode(viewModel: UsageViewModel) -> MetricMode {
        let autoMetricMode = UserDefaults.standard.bool(forKey: UserDefaultsKeys.autoMetricMode)
        if autoMetricMode, let snapshot = viewModel.snapshot {
            return snapshot.autoResolvedMode
        }
        let raw = UserDefaults.standard.string(forKey: UserDefaultsKeys.metricMode) ?? "5h"
        return MetricMode(rawValue: raw) ?? .fiveHour
    }

    private func resolveStarColor(metricMode: MetricMode, percent: Double, isThrottled: Bool) -> NSColor {
        if isThrottled {
            return ThemeColors.barNSColor(percent: 100)
        } else if metricMode == .contextHealth {
            return ThemeColors.contextHealthNSColor(percent: percent)
        } else {
            return ThemeColors.barNSColor(percent: percent)
        }
    }

    private func updateSparkleState(isThrottled: Bool) {
        if hasReceivedFirstUpdate && currentIsThrottled && !isThrottled {
            startRecoverySparkle()
        }
        if isThrottled {
            stopRecoverySparkle()
        }
    }

    private func updateRenderState(percent: Double, color: NSColor, isThrottled: Bool) {
        currentPercent = percent
        currentColor = color
        currentIsThrottled = isThrottled
        hasReceivedFirstUpdate = true
    }

    private func resolveDisplayText(rateLimits: RateLimitUsage?, percent: Double) -> String {
        if let rl = rateLimits, let resetDate = countdownResetDate(for: rl) {
            return RateLimitUsage.countdownText(to: resetDate)
        }
        return "\(Int(percent))%"
    }

    /// Returns the reset date for countdown display when throttled or any window hits 100%.
    /// Priority: binding reset when throttled, otherwise earliest reset of any exhausted window.
    private func countdownResetDate(for rateLimits: RateLimitUsage) -> Date? {
        if rateLimits.isThrottled {
            return rateLimits.bindingReset
        }

        let fiveExhausted = rateLimits.fiveHourPercent >= 100
        let sevenExhausted = rateLimits.sevenDayPercent >= 100

        if fiveExhausted && sevenExhausted {
            // Both exhausted — show earliest reset
            if let f = rateLimits.fiveHourReset, let s = rateLimits.sevenDayReset {
                return min(f, s)
            }
            return rateLimits.fiveHourReset ?? rateLimits.sevenDayReset
        } else if fiveExhausted {
            return rateLimits.fiveHourReset
        } else if sevenExhausted {
            return rateLimits.sevenDayReset
        }

        return nil
    }

    // MARK: - Recovery sparkle (throttle → green transition)

    private func startRecoverySparkle() {
        isSparkleActive = true
        sparkleTimer?.invalidate()
        sparkleTimer = Timer.scheduledTimer(withTimeInterval: Self.sparkleDuration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stopRecoverySparkle()
            }
        }
    }

    private func stopRecoverySparkle() {
        isSparkleActive = false
        sparkleTimer?.invalidate()
        sparkleTimer = nil
    }

    // MARK: - Panel toggle

    @objc private func statusItemClicked() {
        let now = Date()
        guard now.timeIntervalSince(lastClickAt) > 0.1 else { return }
        lastClickAt = now
        guard let panel, let button = statusItem?.button else { return }
        let action = toggleState.toggle()
        switch action {
        case .hide:
            panel.orderOut(nil)
        case .show:
            positionPanel(relativeTo: button)
            os_signpost(.begin, log: panelShowLog, name: "PanelShow")
            panel.orderFrontRegardless()
            panel.makeKey()
            os_signpost(.end, log: panelShowLog, name: "PanelShow")
        }
    }

    private func positionPanel(relativeTo button: NSStatusBarButton) {
        guard let panel, let buttonWindow = button.window else { return }
        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)

        let panelWidth = panel.frame.width
        let panelHeight = panel.frame.height
        let margin: CGFloat = 4

        // Prefer left-align to status item; flip to right-align if panel would overflow
        var x: CGFloat
        if let screen = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame {
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
}

// MARK: - Panel subclass

/// Borderless panel that can become key (accepts keyboard events).
/// `hidesOnDeactivate` must return false — LSUIElement menu bar apps don't maintain
/// proper activation state, so the panel would auto-hide immediately after showing.
/// Manual click-outside + deactivation observers handle dismissal instead.
/// `onDismiss` is called for every orderOut path, including system-initiated ones,
/// ensuring toggleState never desyncs.
private class PopoverPanel: NSPanel {
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
private struct PopoverContentView: View {
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
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
