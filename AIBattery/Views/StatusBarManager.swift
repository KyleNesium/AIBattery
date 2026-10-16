import SwiftUI
import AppKit
import Combine
@preconcurrency import Dispatch
import os.signpost

extension Notification.Name {
    /// Keyboard shortcut pressed in the popover panel — forwarded to SwiftUI views.
    static let panelKeyPress = Notification.Name("panelKeyPress")
    /// Panel was dismissed (any path) — SwiftUI views reset transient state.
    static let panelDidDismiss = Notification.Name("panelDidDismiss")
    /// Panel was ordered front. `orderOut` never fires SwiftUI's `onDisappear` (the
    /// hosting view stays in the hierarchy), so `onAppear` won't re-fire either —
    /// this is the re-arm signal for the deferred heavy sections after a re-open.
    static let panelDidShow = Notification.Name("panelDidShow")
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
///
/// Split across extension files (v2.4.0 precedent — same shape as UsageViewModel):
/// - `StatusBarManager+ButtonUpdate.swift` — menu-bar image rendering + recovery sparkle
/// - `StatusBarManager+Countdown.swift` — countdown ticker + reset-date resolution
/// - `StatusBarManager+Panel.swift` — panel toggle/positioning + panel/hosting types
///
/// Stored state the extensions touch is declared without `private` so it stays
/// visible across the extension files in the same module (extensions in other
/// files cannot see `private` members).
@MainActor
public final class StatusBarManager: NSObject {
    var statusItem: NSStatusItem?
    var panel: PopoverPanel?
    var hostingView: TransparentHostingView<PopoverContentView>?
    /// Asked before Escape closes the panel: the SwiftUI root returns true when it
    /// consumed the key itself (e.g. the detail view stepped back to the overview).
    /// Set by `PopoverContentView` on appear.
    var escapeHandler: (() -> Bool)?
    weak var viewModel: UsageViewModel?
    private var cancellables = Set<AnyCancellable>()
    /// Last observed values of the two preferences that change what the menu bar
    /// draws — used to filter the `UserDefaults.didChangeNotification` firehose down
    /// to actual flips of those keys.
    private var lastObservedShowAllAccounts: Bool = UserDefaults.standard.bool(forKey: UserDefaultsKeys.showAllAccountsInMenuBar)
    private var lastObservedColorblind: Bool = UserDefaults.standard.bool(forKey: UserDefaultsKeys.colorblindMode)
    // NSEvent monitors / observers / Timers touched by the nonisolated deinit;
    // `nonisolated(unsafe)` is required so the deinit can clean them up.
    // Documented thread-safe cleanup APIs.
    nonisolated(unsafe) private var escapeMonitor: Any?
    nonisolated(unsafe) private var clickOutsideMonitor: Any?
    /// Toggle state machine — tracks intended panel visibility.
    /// All dismiss paths (including system-initiated orderOut) call toggleState.dismiss() via onDismiss callback.
    var toggleState = PanelToggleState()
    nonisolated(unsafe) private var deactivationObserver: Any?
    let panelShowLog = OSLog(subsystem: "com.kylenesium.AIBattery", category: .pointsOfInterest)
    /// Timestamp of last click — debounces rapid clicks during toggle.
    var lastClickAt: Date = .distantPast
    nonisolated(unsafe) private var appearanceObserver: NSKeyValueObservation?
    nonisolated(unsafe) private var buttonAppearanceObserver: NSKeyValueObservation?
    nonisolated(unsafe) private var frameObserver: Any?
    /// Debounce token for the panel-resize observer below. Stored on the
    /// MainActor-isolated instance so it can be mutated from the @Sendable
    /// NotificationCenter observer closure without racing.
    private var resizeWorkItem: DispatchWorkItem?
    /// Absolute Y coordinate of the panel's top edge (just below the menu bar).
    /// Set by `positionPanel` and used by the resize observer to keep the top anchored.
    /// Re-derived in the resize observer so display/geometry changes don't detach the panel.
    var panelTopY: CGFloat = 0

    /// Gap between the menu bar button and the panel's top edge.
    static let panelMargin: CGFloat = 4

    // Snapshot of current render state. Only the throttle flag is read back (to detect
    // a real transition); the percent and colour were written every update and never
    // consulted, so they are not kept.
    var currentIsThrottled: Bool = false
    /// Whether we've received at least one update (so we can detect real transitions vs initial state).
    var hasReceivedFirstUpdate: Bool = false

    /// Key describing the last menu-bar image actually rendered — `updateButton`
    /// skips the NSAttributedString+NSImage rebuild when nothing visible changed
    /// (countdown ticks fire every 10s; the text changes ~once a minute).
    var lastRenderKey: MenuBarRenderKey?

    // Recovery sparkle: 30s celebration after throttle clears
    var isSparkleActive: Bool = false
    nonisolated(unsafe) var sparkleTimer: Timer?
    /// Duration of the recovery sparkle effect after throttle clears.
    static let sparkleDuration: TimeInterval = 30

    // Countdown ticker: 1s timer to keep menu bar countdown in sync with popover
    nonisolated(unsafe) var countdownTimer: Timer?
    /// The reset date currently being counted down to (nil = no active countdown).
    var activeResetDate: Date?

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
            rootView: PopoverContentView(
                viewModel: viewModel,
                oauthManager: oauthManager,
                registerEscapeHandler: { [weak self] handler in self?.escapeHandler = handler }
            )
        )
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = Layout.iconClipRadius
        hosting.layer?.masksToBounds = true

        panel.contentView = hosting
        panel.setContentSize(NSSize(width: Layout.popoverWidth, height: Layout.panelInitialHeight))

        // Resize panel when SwiftUI content changes height.
        // Two triggers feed one debounced refit (`scheduleRefit`):
        //  1. `onIntrinsicSizeInvalidated` — SwiftUI reports that the hosted tree's
        //     ideal size changed. This is the cause, and the only trigger guaranteed
        //     to fire: the Settings toggle intermittently produced no frame change at
        //     all, leaving the panel at its old height with the content clipped.
        //  2. `frameDidChangeNotification` — AppKit's window auto-layout resized the
        //     hosting view as a side effect; kept so the top edge is re-anchored
        //     whenever the frame moves for any other reason.
        hosting.setContentHuggingPriority(.defaultHigh, for: .vertical)
        hosting.postsFrameChangedNotifications = true
        hosting.onIntrinsicSizeInvalidated = { [weak self] in
            self?.scheduleRefit()
        }
        frameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: hosting,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleRefit()
            }
        }

        // React to snapshot, staleness, or per-account map changes — debounced to avoid rapid-fire redraws.
        // The third publisher (perAccountReadings) ensures the menu bar redraws when the
        // multi-account fan-out completes, even when the active-account snapshot is unchanged.
        viewModel.$snapshot
            .combineLatest(viewModel.$lastFreshFetch, viewModel.$perAccountReadings)
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self, weak item, weak viewModel] _ in
                guard let self, let button = item?.button, let viewModel else { return }
                self.updateButton(button, viewModel: viewModel)
            }
            .store(in: &cancellables)

        // Preference observer: when the user flips "Show all accounts in menu bar" or
        // the colorblind palette, redraw the button immediately rather than waiting for
        // the next refresh tick (up to 5 min). Filter to actual flips of those two keys —
        // `UserDefaults.didChangeNotification` fires on every preference write, and
        // unrelated changes (slider drags) must not thrash the menu bar redraw path.
        // The colorblind flip must also defeat the render-key skip: the key holds the
        // star colour, which `ThemeColors` has already re-derived by the time this runs.
        NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self, weak item, weak viewModel] _ in
                guard let self, let button = item?.button, let viewModel else { return }
                let showAll = UserDefaults.standard.bool(forKey: UserDefaultsKeys.showAllAccountsInMenuBar)
                let colorblind = UserDefaults.standard.bool(forKey: UserDefaultsKeys.colorblindMode)
                let showAllFlipped = showAll != self.lastObservedShowAllAccounts
                let colorblindFlipped = colorblind != self.lastObservedColorblind
                guard showAllFlipped || colorblindFlipped else { return }
                self.lastObservedShowAllAccounts = showAll
                self.lastObservedColorblind = colorblind
                self.updateButton(button, viewModel: viewModel)
            }
            .store(in: &cancellables)

        // Refresh on auth change. `dropFirst` skips the value `@Published` replays on
        // subscription: at launch that fired a refresh at t≈0 on top of the view model's
        // own `initialPollDelay` refresh two seconds later. Only real flips (sign-out →
        // sign-in, including re-auth while the panel is open) refresh from here.
        oauthManager.$isAuthenticated
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] authenticated in
                if authenticated {
                    Task { @MainActor [weak self] in
                        // The refresh runs FIRST so its awaits give SwiftUI runloop
                        // cycles to commit the AuthView → UsagePopoverView structural
                        // swap; only then re-arm the popover's deferred sections if the
                        // auth flip happened while the panel is open. Signing out swaps
                        // UsagePopoverView for AuthView (structural removal →
                        // onDisappear disarms); signing back in re-inserts it with no
                        // panel close/reopen, so .panelDidShow never re-fires and
                        // Projects/Insights would stay collapsed on a visible panel.
                        // Posting before the refresh raced the view insertion — the new
                        // view's .onReceive subscription may not exist yet, and a
                        // notification with no subscriber is silently dropped.
                        await viewModel.refresh()
                        if let self, self.toggleState.isShowing {
                            NotificationCenter.default.post(name: .panelDidShow, object: nil)
                        }
                    }
                }
            }
            .store(in: &cancellables)

        // Close panel on Escape key.
        // onDismiss fires from PopoverPanel.orderOut — no redundant dismiss() call needed.
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53, let self, self.toggleState.isShowing {
                if self.escapeHandler?() == true {
                    return nil // consumed by the popover (back to the overview)
                }
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
                if buttonWindow.frame.contains(screenPoint) {
                    return
                }
            }
            // Ignore clicks on our own panel
            if let panel = self.panel, panel.frame.contains(NSEvent.mouseLocation) {
                return
            }
            self.panel?.orderOut(nil)
        }

        // Track system appearance changes so the panel follows light/dark mode.
        //
        // KVO callbacks for `effectiveAppearance` are not contractually main-thread, so
        // hop explicitly via `Task { @MainActor in ... }` rather than asserting isolation.
        appearanceObserver = NSApp.observe(\.effectiveAppearance) { [weak panel] _, _ in
            // Re-capture weakly inside the Task body: Swift 5 mode's checker
            // rejects accessing the outer closure's `weak` captures from a
            // concurrent task (they're `var` semantically).
            Task { @MainActor [weak panel] in
                panel?.appearance = NSApp.effectiveAppearance
            }
        }

        // Rebuild the menu bar image when the BUTTON's appearance changes.
        // `combinedStatusBarImage` bakes the text colour (black/white) at render time from
        // `button.effectiveAppearance` — the menu bar's own backdrop (wallpaper tint,
        // translucency), which can differ from `NSApp.effectiveAppearance` and change
        // without it (new wallpaper, moving to another display). Observing NSApp here left
        // stale text until the next poll; the button is what the render actually reads.
        if let button = item.button {
            buttonAppearanceObserver = button.observe(\.effectiveAppearance) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self,
                          let button = self.statusItem?.button,
                          let viewModel = self.viewModel else { return }
                    self.updateButton(button, viewModel: viewModel)
                }
            }
        }

        // Close panel when app loses focus (Cmd+Tab, click another app's window).
        // onDismiss fires from PopoverPanel.orderOut — no redundant dismiss() call needed.
        deactivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            // `queue: .main` makes the callback main-thread; the cast to MainActor
            // isolation is sound but Swift can't infer it across `@Sendable` boundaries.
            MainActor.assumeIsolated {
                guard let self, self.toggleState.isShowing else { return }
                self.panel?.orderOut(nil)
            }
        }

        self.statusItem = item
        self.panel = panel
        self.hostingView = hosting

        // Pre-warm: force SwiftUI's first layout pass now (at startup) so the first
        // user click doesn't pay the ~500ms+ layout cost. Show the panel offscreen
        // for one frame, then hide it.
        panel.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        panel.orderFrontRegardless()
        DispatchQueue.main.async {
            panel.orderOut(nil)
        }
    }

    /// Debounced refit of the panel to the hosting view's fitting size, top edge pinned
    /// to the status item. Safe to call on every layout tick; only the last call in a
    /// 16 ms window does work. Max height is screen-relative so all sections fit on
    /// most displays.
    func scheduleRefit() {
        resizeWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.refitPanelToContent()
            }
        }
        resizeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.016, execute: work)
    }

    private func refitPanelToContent() {
        guard let panel, let hosting = hostingView else { return }
        guard toggleState.isShowing else { return }
        let screenMaxHeight = panel.screen?.visibleFrame.height ?? Layout.fallbackScreenHeight
        let maxPanelHeight = screenMaxHeight - Layout.menuBarInset
        // One read: each access to `fittingSize` runs a SwiftUI layout pass, and this
        // method runs on every content size change.
        let fitting = hosting.fittingSize
        let fittingHeight = min(fitting.height, maxPanelHeight)
        let newHeight = max(fittingHeight, Layout.panelMinHeight)
        // Skip no-op frame updates to avoid layout feedback loops
        guard abs(newHeight - panel.frame.height) > 0.5 else { return }
        // Re-derive the top anchor from the status button's current screen
        // position. `panelTopY` can go stale across display/geometry changes,
        // which caused the panel to float detached from the menu bar after
        // a settings expand/collapse cycle.
        let topAnchor = currentTopAnchor() ?? panelTopY
        panelTopY = topAnchor
        // Grow downward from top anchor
        let newOrigin = NSPoint(
            x: panel.frame.origin.x,
            y: topAnchor - newHeight
        )
        let fittingWidth = max(fitting.width, Layout.popoverWidth)
        panel.setFrame(
            NSRect(origin: newOrigin, size: NSSize(width: fittingWidth, height: newHeight)),
            display: true,
            animate: false
        )
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
        if let obs = frameObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        appearanceObserver?.invalidate()
        buttonAppearanceObserver?.invalidate()
        sparkleTimer?.invalidate()
        countdownTimer?.invalidate()
    }
}
