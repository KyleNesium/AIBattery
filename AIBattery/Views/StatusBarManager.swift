import SwiftUI
import AppKit
import Combine

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
    /// Tracks intended panel visibility — used to re-show panel after app deactivation.
    private var isPanelShowing = false
    private var deactivationObserver: Any?
    private var appearanceObserver: NSKeyValueObservation?
    private var frameObserver: Any?
    /// Absolute Y coordinate of the panel's top edge (just below the menu bar).
    /// Set by `positionPanel` and used by the resize observer to keep the top anchored.
    private var panelTopY: CGFloat = 0

    // Breathing glow animation state
    private var breathTimer: Timer?
    private var currentPulseStep: Int = 0
    // Snapshot of current render state for the breath timer callback
    private var currentPercent: Double = 0
    private var currentColor: NSColor = .systemGreen
    private var currentIsThrottled: Bool = false
    /// Whether we've received at least one update (so we can detect real transitions vs initial state).
    private var hasReceivedFirstUpdate: Bool = false
    private var screenSleepObserver: Any?
    private var screenWakeObserver: Any?

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
            // macOS menu bar uses ~12pt for status items; battery percentage matches this.
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
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
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .none

        // Follow system light/dark appearance so the popover material matches the OS theme
        panel.appearance = NSApp.effectiveAppearance

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
        panel.setContentSize(NSSize(width: 275, height: 700))

        // Resize panel when SwiftUI content changes height.
        // Max height is screen-relative so all sections fit on most displays.
        hosting.setContentHuggingPriority(.defaultHigh, for: .vertical)
        hosting.postsFrameChangedNotifications = true
        frameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: hosting,
            queue: .main
        ) { [weak panel, weak hosting, weak self] _ in
            MainActor.assumeIsolated {
                guard let panel, let hosting, let self else { return }
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
                panel.setFrame(
                    NSRect(origin: newOrigin, size: NSSize(width: 275, height: newHeight)),
                    display: true,
                    animate: false
                )
            }
        }

        // React to snapshot or staleness changes — single subscription avoids double updates
        viewModel.$snapshot
            .combineLatest(viewModel.$lastFreshFetch)
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

        // Close panel on Escape key
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53, let self, self.isPanelShowing {
                self.panel?.orderOut(nil)
                self.isPanelShowing = false
                return nil
            }
            return event
        }

        // Close panel when clicking outside (global mouse events from other apps)
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.isPanelShowing else { return }
            Task { @MainActor in
                self.panel?.orderOut(nil)
                self.isPanelShowing = false
            }
        }

        // Track system appearance changes so the panel follows light/dark mode
        appearanceObserver = NSApp.observe(\.effectiveAppearance) { [weak panel] _, _ in
            panel?.appearance = NSApp.effectiveAppearance
        }

        // Close panel when app loses focus (e.g., user switches to another app via Cmd+Tab)
        deactivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPanelShowing else { return }
                self.panel?.orderOut(nil)
                self.isPanelShowing = false
            }
        }

        self.statusItem = item
        self.panel = panel
        self.hostingView = hosting
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
        breathTimer?.invalidate()
        sparkleTimer?.invalidate()
        if let obs = screenSleepObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = screenWakeObserver { NotificationCenter.default.removeObserver(obs) }
    }

    // MARK: - Button update

    private func updateButton(_ button: NSStatusBarButton, viewModel: UsageViewModel) {
        let metricMode = resolveMetricMode(viewModel: viewModel)
        let percent = viewModel.snapshot?.percent(for: metricMode) ?? 0
        let rateLimits = viewModel.snapshot?.rateLimits
        let isThrottled = rateLimits?.isThrottled ?? false
        let starColor = resolveStarColor(metricMode: metricMode, percent: percent, isThrottled: isThrottled)

        updateSparkleState(isThrottled: isThrottled)
        updateRenderState(percent: percent, color: starColor, isThrottled: isThrottled)
        updateBreathTimer(percent: percent, isThrottled: isThrottled)

        button.image = MenuBarIcon.statusBarImage(
            for: percent,
            color: starColor,
            isBroken: isThrottled,
            isSparkle: isSparkleActive,
            pulseStep: currentPulseStep
        )

        let displayText = resolveDisplayText(rateLimits: rateLimits, percent: percent)
        button.title = displayText
        button.setAccessibilityValue(displayText)
        button.appearsDisabled = isStale(lastFetch: viewModel.lastFreshFetch)
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

    private func updateBreathTimer(percent: Double, isThrottled: Bool) {
        if isThrottled {
            stopBreathTimer()
        } else if isSparkleActive || percent >= 95 {
            startBreathTimerIfNeeded()
        } else {
            stopBreathTimer()
        }
    }

    private func resolveDisplayText(rateLimits: RateLimitUsage?, percent: Double) -> String {
        if let rl = rateLimits, let resetDate = countdownResetDate(for: rl) {
            return RateLimitUsage.countdownText(to: resetDate)
        }
        return "\(Int(percent))%"
    }

    private func isStale(lastFetch: Date?) -> Bool {
        guard let lastFetch else { return false }
        return Date().timeIntervalSince(lastFetch) > 300
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

    // MARK: - Breath timer

    /// Breathing cycle: 4s per full cycle, discrete steps.
    /// Sparkle mode: 8 steps (500ms per tick) for smooth twinkling.
    /// Red band (≥95%): 4 steps (1s per tick) — halves CPU wakeups with imperceptible visual change.
    /// Pauses on screen sleep.
    private var breathTimerStepSize: Int = 1

    private func startBreathTimerIfNeeded() {
        // Red band uses every-other step (4 wakeups/cycle); sparkle uses every step (8 wakeups/cycle).
        let newStepSize = isSparkleActive ? 1 : 2
        // Restart timer if step size changed (e.g. sparkle → red transition)
        if breathTimer != nil && breathTimerStepSize != newStepSize {
            stopBreathTimer()
        }
        guard breathTimer == nil else { return }
        breathTimerStepSize = newStepSize

        // Observe screen sleep/wake to pause animation when display is off
        if screenSleepObserver == nil {
            screenSleepObserver = NotificationCenter.default.addObserver(
                forName: NSWorkspace.screensDidSleepNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.stopBreathTimer() }
            }
            screenWakeObserver = NotificationCenter.default.addObserver(
                forName: NSWorkspace.screensDidWakeNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.startBreathTimerIfNeeded() }
            }
        }

        let interval: TimeInterval = 4.0 / Double(MenuBarIcon.pulseSteps) * Double(newStepSize)
        breathTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let button = self.statusItem?.button else { return }
                self.currentPulseStep = (self.currentPulseStep + self.breathTimerStepSize) % MenuBarIcon.pulseSteps
                button.image = MenuBarIcon.statusBarImage(
                    for: self.currentPercent,
                    color: self.currentColor,
                    isBroken: self.currentIsThrottled,
                    isSparkle: self.isSparkleActive,
                    pulseStep: self.currentPulseStep
                )
            }
        }
    }

    private func stopBreathTimer() {
        breathTimer?.invalidate()
        breathTimer = nil
        currentPulseStep = 0
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
        guard let panel, let button = statusItem?.button else { return }
        if isPanelShowing {
            panel.orderOut(nil)
            isPanelShowing = false
        } else {
            positionPanel(relativeTo: button)
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            isPanelShowing = true
        }
    }

    private func positionPanel(relativeTo button: NSStatusBarButton) {
        guard let panel, let buttonWindow = button.window else { return }
        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)

        let panelWidth = panel.frame.width
        let panelHeight = panel.frame.height

        // Left-align panel to the status item's left edge
        var x = screenRect.minX
        let y = screenRect.minY - panelHeight - 4

        if let screen = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame {
            x = max(screen.minX + 4, min(x, screen.maxX - panelWidth - 4))
        }

        // Store absolute top anchor so the resize observer can keep top pinned
        panelTopY = screenRect.minY - 4

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

// MARK: - Panel subclass

/// Borderless panel that can become key (accepts keyboard events).
/// Overrides `hidesOnDeactivate` to always return false — prevents SwiftUI's
/// app lifecycle from hiding the panel when the app loses focus.
private class PopoverPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var hidesOnDeactivate: Bool {
        get { false }
        set { /* ignore — panel must stay visible regardless of app activation */ }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            orderOut(nil)
        } else if event.keyCode == 12 && event.modifierFlags.contains(.command) { // Cmd+Q
            NSApplication.shared.terminate(nil)
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
        .frame(width: 275)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
