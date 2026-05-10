import SwiftUI
import AppKit
import Combine
import os.signpost

extension Notification.Name {
    /// Keyboard shortcut pressed in the popover panel — forwarded to SwiftUI views.
    static let panelKeyPress = Notification.Name("panelKeyPress")
    /// Panel was dismissed (any path) — SwiftUI views reset transient state.
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
    private var hostingView: TransparentHostingView<PopoverContentView>?
    private weak var viewModel: UsageViewModel?
    private var cancellables = Set<AnyCancellable>()
    /// Last observed value of the multi-account toggle — used to filter the
    /// `UserDefaults.didChangeNotification` firehose down to actual toggle flips.
    private var lastObservedShowAllAccounts: Bool = UserDefaults.standard.bool(forKey: UserDefaultsKeys.showAllAccountsInMenuBar)
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
    /// Re-derived in the resize observer so display/geometry changes don't detach the panel.
    private var panelTopY: CGFloat = 0

    /// Gap between the menu bar button and the panel's top edge.
    private static let panelMargin: CGFloat = 4

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

    // Countdown ticker: 1s timer to keep menu bar countdown in sync with popover
    private var countdownTimer: Timer?
    /// The reset date currently being counted down to (nil = no active countdown).
    private var activeResetDate: Date?

    public override init() {
        super.init()
    }

    public func setup(viewModel: UsageViewModel, oauthManager: OAuthManager) {
        self.viewModel = viewModel
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Configure native AppKit button (no NSHostingView — doesn't render in NSStatusBarButton)
        if let button = item.button {
            button.image = MenuBarIcon.statusBarImage(for: 0, color: ThemeColors.barNSColor(percent: 0), menuBarAppearance: button.effectiveAppearance)
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

        let hosting = TransparentHostingView(
            rootView: PopoverContentView(viewModel: viewModel, oauthManager: oauthManager)
        )
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = Layout.iconClipRadius
        hosting.layer?.masksToBounds = true

        panel.contentView = hosting
        panel.setContentSize(NSSize(width: Layout.popoverWidth, height: Layout.panelInitialHeight))

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
                    let screenMaxHeight = panel.screen?.visibleFrame.height ?? Layout.fallbackScreenHeight
                    let maxPanelHeight = screenMaxHeight - Layout.menuBarInset
                    let fittingHeight = min(hosting.fittingSize.height, maxPanelHeight)
                    let newHeight = max(fittingHeight, Layout.panelMinHeight)
                    // Skip no-op frame updates to avoid layout feedback loops
                    guard abs(newHeight - panel.frame.height) > 0.5 else { return }
                    // Re-derive the top anchor from the status button's current screen
                    // position. `panelTopY` can go stale across display/geometry changes,
                    // which caused the panel to float detached from the menu bar after
                    // a settings expand/collapse cycle.
                    let topAnchor = self.currentTopAnchor() ?? self.panelTopY
                    self.panelTopY = topAnchor
                    // Grow downward from top anchor
                    let newOrigin = NSPoint(
                        x: panel.frame.origin.x,
                        y: topAnchor - newHeight
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

        // React to snapshot, staleness, or per-account map changes — debounced to avoid rapid-fire redraws.
        // The third publisher (perAccountRateLimits) ensures the menu bar redraws when the
        // multi-account fan-out completes, even when the active-account snapshot is unchanged.
        viewModel.$snapshot
            .combineLatest(viewModel.$lastFreshFetch, viewModel.$perAccountRateLimits)
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self, weak item, weak viewModel] _ in
                guard let self, let button = item?.button, let viewModel else { return }
                self.updateButton(button, viewModel: viewModel)
            }
            .store(in: &cancellables)

        // Toggle observer: when the user flips "Show all accounts in menu bar", redraw
        // the button immediately rather than waiting for the next refresh tick (up to 30 s).
        // Filter to actual toggle flips — `UserDefaults.didChangeNotification` fires
        // on every preference write, and we don't want unrelated changes (slider drags,
        // colorblind toggle) to thrash the menu bar redraw path.
        NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self, weak item, weak viewModel] _ in
                guard let self, let button = item?.button, let viewModel else { return }
                let current = UserDefaults.standard.bool(forKey: UserDefaultsKeys.showAllAccountsInMenuBar)
                guard current != self.lastObservedShowAllAccounts else { return }
                self.lastObservedShowAllAccounts = current
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
                let screenPoint = event.window.map { $0.convertPoint(toScreen: event.locationInWindow) }
                    ?? event.locationInWindow
                if buttonWindow.frame.contains(screenPoint) { return }
            }
            // Ignore clicks on our own panel
            if let panel = self.panel, panel.frame.contains(NSEvent.mouseLocation) { return }
            self.panel?.orderOut(nil)
        }

        // Track system appearance changes so the panel follows light/dark mode.
        // Also rebuild the menu bar image: `combinedStatusBarImage` bakes the text color
        // (black/white) at render time from the then-current effective appearance, so a
        // dark/light or "Increase Contrast" switch leaves stale text until the next poll
        // unless we force a redraw here.
        //
        // KVO callbacks for `effectiveAppearance` are not contractually main-thread, so
        // hop explicitly via `Task { @MainActor in ... }` rather than asserting isolation.
        // Both the panel mutation and the status-bar redraw are AppKit UI work.
        appearanceObserver = NSApp.observe(\.effectiveAppearance) { [weak self, weak panel] _, _ in
            Task { @MainActor in
                panel?.appearance = NSApp.effectiveAppearance
                guard let self,
                      let button = self.statusItem?.button,
                      let viewModel = self.viewModel else { return }
                self.updateButton(button, viewModel: viewModel)
            }
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
        countdownTimer?.invalidate()
    }

    // MARK: - Button update

    private func updateButton(_ button: NSStatusBarButton, viewModel: UsageViewModel) {
        let metricMode = resolveMetricMode(viewModel: viewModel)
        let activePercent = viewModel.snapshot?.percent(for: metricMode) ?? 0
        let activeRateLimits = viewModel.snapshot?.rateLimits
        let activeIsThrottled = activeRateLimits?.isThrottled ?? false
        // Show broken star when throttled OR any window hits 100%.
        let activeIsExhausted = activeIsThrottled
            || (activeRateLimits?.fiveHourPercent ?? 0) >= 100
            || (activeRateLimits?.sevenDayPercent ?? 0) >= 100

        // Multi-account branch: when toggle is on and ≥2 authenticated accounts exist,
        // render text from the per-account map and key the icon visuals to the worst
        // account. Gating on the *authenticated* count (not perAccount.count) means a
        // second account whose fan-out hasn't completed yet still gets a "—" slot
        // instead of dropping us back to the single-account renderer.
        let showAll = UserDefaults.standard.bool(forKey: UserDefaultsKeys.showAllAccountsInMenuBar)
        let perAccount = viewModel.perAccountRateLimits
        // Skip pending accounts — their fan-out is filtered out (no real org ID), so
        // including them would render a "—" for an account the user hasn't even
        // authenticated yet.
        let order = OAuthManager.shared.accountStore.accounts
            .filter { !$0.isPendingIdentity }
            .map(\.id)
        let useMulti = MenuBarMultiAccountText.shouldRender(toggleOn: showAll, accountCount: order.count)

        let percent: Double
        let isExhausted: Bool
        let displayText: String
        let countdownReset: Date?
        if useMulti {
            let multi = MenuBarMultiAccountText.build(order: order, limits: perAccount, metricMode: metricMode)
            // Worst across accounts drives star color/breath. Floor at active so the active
            // account's icon doesn't visually shrink when secondaries are present.
            percent = max(multi.worstPercent, activePercent)
            isExhausted = multi.anyThrottled || activeIsExhausted
            // Countdown only when an account is actually exhausted — `countdownResetDate`
            // returns nil for healthy accounts. Without this filter, a healthy account's
            // future 5H reset would pin the menu bar into countdown mode and hide the
            // new "X% | Y%" text entirely.
            let now = Date()
            let multiReset = perAccount.values
                .compactMap { Self.countdownResetDate(for: $0, now: now) }
                .min()
            let activeReset = activeRateLimits.flatMap { countdownResetDate(for: $0) }
            countdownReset = [multiReset, activeReset].compactMap { $0 }.min()
            if let reset = countdownReset {
                displayText = RateLimitUsage.countdownText(to: reset)
            } else {
                displayText = multi.text
            }
        } else {
            percent = activePercent
            isExhausted = activeIsExhausted
            displayText = resolveDisplayText(rateLimits: activeRateLimits, percent: activePercent)
            countdownReset = activeRateLimits.flatMap { countdownResetDate(for: $0) }
        }

        let isDarkMenuBar = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let starColor = resolveStarColor(metricMode: metricMode, percent: percent, isThrottled: isExhausted, isDarkMenuBar: isDarkMenuBar)

        updateSparkleState(isThrottled: isExhausted)
        updateRenderState(percent: percent, color: starColor, isThrottled: isExhausted)

        button.image = MenuBarIcon.combinedStatusBarImage(
            text: displayText,
            percent: percent,
            color: starColor,
            isBroken: isExhausted,
            isSparkle: isSparkleActive,
            menuBarAppearance: button.effectiveAppearance
        )
        // Title is baked into the image — leaving it set would add AppKit's bezel padding
        // back around the text, which is exactly what we're avoiding here.
        button.title = ""
        button.setAccessibilityValue(displayText)
        updateStatusItemWidth(button: button)
        // Never grey out — the icon always shows the last known state.
        // Other menu bar apps (Battery, WiFi) don't dim on stale data.

        // Start or stop the countdown ticker based on whether we have an active countdown.
        if let resetDate = countdownReset {
            startCountdownTimer(resetDate: resetDate, button: button)
        } else {
            stopCountdownTimer()
        }
    }

    private func resolveMetricMode(viewModel: UsageViewModel) -> MetricMode {
        let autoMetricMode = UserDefaults.standard.bool(forKey: UserDefaultsKeys.autoMetricMode)
        if autoMetricMode {
            return viewModel.resolvedMetricMode
        }
        let raw = UserDefaults.standard.string(forKey: UserDefaultsKeys.metricMode) ?? "5h"
        return MetricMode(rawValue: raw) ?? .fiveHour
    }

    private func updateStatusItemWidth(button: NSStatusBarButton) {
        guard let statusItem, let image = button.image else { return }
        // Setting `statusItem.length = image.size.width` (rather than + 2) eliminates
        // the 1pt-per-side `NSButton` image-centering padding: when button width equals
        // image width, `imageRect(forBounds:)` returns origin.x = 0 and the image is
        // flush against both edges.
        //
        // The remaining `NSStatusBarWindow` chrome of 8pt on each side (total window
        // width = length + 16) is enforced by AppKit for third-party `NSStatusItem`s
        // and cannot be eliminated via public API — system items like Battery / WiFi
        // render inside ControlCenter's private content view which bypasses it.
        statusItem.length = image.size.width
    }

    private func resolveStarColor(metricMode: MetricMode, percent: Double, isThrottled: Bool, isDarkMenuBar: Bool) -> NSColor {
        if isThrottled {
            return ThemeColors.barNSColor(percent: 100)
        } else if metricMode == .contextHealth {
            return ThemeColors.contextHealthNSColor(percent: percent)
        } else {
            return ThemeColors.barNSColor(percent: percent, isDarkMenuBar: isDarkMenuBar)
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
    /// Priority: binding reset when throttled, otherwise earliest *future* reset of any
    /// exhausted window. Past dates are filtered out — the window has already reset, so
    /// another (still-future) window's countdown should take over instead of dropping to
    /// a stale percentage.
    private func countdownResetDate(for rateLimits: RateLimitUsage) -> Date? {
        Self.countdownResetDate(for: rateLimits, now: .now)
    }

    /// Pure, deterministic version of `countdownResetDate(for:)` — exposed at file scope
    /// and parameterized on `now` so tests can assert handoff behaviour between the
    /// 5-hour and 7-day windows without having to pin wall-clock time.
    /// `nonisolated` because the implementation only reads its arguments — no shared
    /// state — so tests can call it synchronously from outside the MainActor.
    nonisolated static func countdownResetDate(for rateLimits: RateLimitUsage, now: Date) -> Date? {
        // Keeps only reset timestamps that are still in the future; the 5-hour reset
        // can fire while the 7-day window is still exhausted, and we want the valid
        // 7-day countdown to take over rather than `min()` locking onto the past one.
        let future: (Date?) -> Date? = { date in
            guard let date, date.timeIntervalSince(now) > 0 else { return nil }
            return date
        }

        if rateLimits.isThrottled {
            return future(rateLimits.bindingReset)
        }

        let fiveExhausted = rateLimits.fiveHourPercent >= 100
        let sevenExhausted = rateLimits.sevenDayPercent >= 100
        let futureFive = fiveExhausted ? future(rateLimits.fiveHourReset) : nil
        let futureSeven = sevenExhausted ? future(rateLimits.sevenDayReset) : nil

        return [futureFive, futureSeven].compactMap { $0 }.min()
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

    // MARK: - Countdown ticker

    /// Starts (or re-uses) a repeating timer that updates the menu bar countdown text
    /// every tick. Tick interval adapts: 1s when <60s remain, 10s otherwise.
    /// This keeps the menu bar countdown in sync with the popover's TimelineView.
    private func startCountdownTimer(resetDate: Date, button: NSStatusBarButton) {
        let interval = countdownTickInterval(for: resetDate)
        // Re-use existing timer if targeting the same reset date at the same interval
        if activeResetDate == resetDate, countdownTimer?.timeInterval == interval {
            return
        }
        stopCountdownTimer()
        activeResetDate = resetDate
        countdownTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self, weak button] _ in
            MainActor.assumeIsolated {
                guard let self, let button, let vm = self.viewModel else { return }
                let remaining = resetDate.timeIntervalSinceNow
                if remaining <= 0 {
                    // Countdown expired — refresh display to show percentage
                    self.stopCountdownTimer()
                    self.updateButton(button, viewModel: vm)
                    return
                }
                // Rebuild the combined image so the baked countdown text updates.
                // `updateButton` also re-evaluates the tick interval via `startCountdownTimer`,
                // which short-circuits when interval/resetDate are unchanged.
                self.updateButton(button, viewModel: vm)
            }
        }
    }

    private func stopCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        activeResetDate = nil
    }

    /// 1s ticks when <60s remain (live countdown feel), 10s otherwise (low overhead).
    private func countdownTickInterval(for resetDate: Date) -> TimeInterval {
        let diff = resetDate.timeIntervalSinceNow
        return (diff > 0 && diff < 60) ? 1 : 10
    }

    // MARK: - Panel toggle

    @objc private func statusItemClicked() {
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

    private func positionPanel(relativeTo button: NSStatusBarButton) {
        guard let panel, let buttonWindow = button.window else { return }
        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)

        let panelWidth = panel.frame.width
        let panelHeight = panel.frame.height
        let margin = Self.panelMargin

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

    /// Returns the panel's ideal top Y coordinate derived from the status button's
    /// current screen position. Nil if the button is not attached to a window.
    private func currentTopAnchor() -> CGFloat? {
        guard let button = statusItem?.button, let buttonWindow = button.window else {
            return nil
        }
        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)
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
