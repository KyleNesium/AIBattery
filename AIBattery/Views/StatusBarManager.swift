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
    /// Tracks intended panel visibility — used to re-show panel after app deactivation.
    private var isPanelShowing = false
    private var deactivationObserver: Any?
    private var appearanceObserver: Any?

    public override init() {
        super.init()
    }

    public func setup(viewModel: UsageViewModel, oauthManager: OAuthManager) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Configure native AppKit button (no NSHostingView — doesn't render in NSStatusBarButton)
        if let button = item.button {
            button.image = MenuBarIcon.statusBarImage(for: 0)
            button.imagePosition = .imageLeading
            button.title = "—"
            // Match macOS battery indicator: system font with monospaced digits
            button.font = .monospacedDigitSystemFont(ofSize: 0, weight: .regular)
            button.action = #selector(statusItemClicked)
            button.target = self
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
        panel.animationBehavior = .utilityWindow

        // Follow system light/dark appearance so the popover material matches the OS theme
        panel.appearance = NSApp.effectiveAppearance

        // Background: translucent vibrancy in dark mode, solid opaque in light mode.
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .popover
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 10
        visualEffect.layer?.masksToBounds = true

        // SwiftUI content
        let hosting = NSHostingView(
            rootView: PopoverContentView(viewModel: viewModel, oauthManager: oauthManager)
        )
        hosting.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
        ])

        panel.contentView = visualEffect
        panel.setContentSize(NSSize(width: 275, height: 600))

        // React to snapshot changes — update button image + title
        viewModel.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak item, weak viewModel] _ in
                guard let self, let button = item?.button, let viewModel else { return }
                self.updateButton(button, viewModel: viewModel)
            }
            .store(in: &cancellables)

        // Also react to lastFreshFetch changes for staleness dimming
        viewModel.$lastFreshFetch
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak item, weak viewModel] _ in
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

        // Track system appearance changes so the panel follows light/dark mode
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main
        ) { [weak panel] _ in
            panel?.appearance = NSApp.effectiveAppearance
        }

        // Fallback: re-show panel if app deactivation hides it despite hidesOnDeactivate override
        deactivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let panel = self.panel, self.isPanelShowing, !panel.isVisible else { return }
                panel.orderFront(nil)
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
        if let observer = deactivationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = appearanceObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    // MARK: - Button update

    private func updateButton(_ button: NSStatusBarButton, viewModel: UsageViewModel) {
        let metricModeRaw = UserDefaults.standard.string(forKey: UserDefaultsKeys.metricMode) ?? "5h"
        let autoMetricMode = UserDefaults.standard.bool(forKey: UserDefaultsKeys.autoMetricMode)

        let metricMode: MetricMode
        if autoMetricMode, let snapshot = viewModel.snapshot {
            metricMode = snapshot.autoResolvedMode
        } else {
            metricMode = MetricMode(rawValue: metricModeRaw) ?? .fiveHour
        }

        let percent = viewModel.snapshot?.percent(for: metricMode) ?? 0
        button.image = MenuBarIcon.statusBarImage(for: percent)

        // Throttle countdown overrides normal percentage display
        let displayText: String
        if let rateLimits = viewModel.snapshot?.rateLimits,
           rateLimits.isThrottled,
           let resetDate = rateLimits.bindingReset {
            displayText = RateLimitUsage.countdownText(to: resetDate)
        } else {
            displayText = "\(Int(percent))%"
        }
        button.title = displayText

        // Staleness dimming: dim when last fresh fetch > 5 minutes ago
        let isStale: Bool
        if let lastFetch = viewModel.lastFreshFetch {
            isStale = Date().timeIntervalSince(lastFetch) > 300
        } else {
            isStale = false
        }
        button.appearsDisabled = isStale
    }

    // MARK: - Panel toggle

    @objc private func statusItemClicked() {
        guard let panel, let button = statusItem?.button else { return }
        if isPanelShowing {
            panel.orderOut(nil)
            isPanelShowing = false
        } else {
            positionPanel(relativeTo: button)
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            isPanelShowing = true
        }
    }

    private func positionPanel(relativeTo button: NSStatusBarButton) {
        guard let panel, let buttonWindow = button.window else { return }
        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)

        let panelWidth = panel.frame.width
        let panelHeight = panel.frame.height

        // Center horizontally below the status item, clamp to screen edges
        var x = screenRect.midX - panelWidth / 2
        let y = screenRect.minY - panelHeight - 4

        if let screen = NSScreen.main?.visibleFrame {
            x = max(screen.minX + 4, min(x, screen.maxX - panelWidth - 4))
        }

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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if oauthManager.isAuthenticated {
                UsagePopoverView(viewModel: viewModel)
            } else {
                AuthView(oauthManager: oauthManager)
            }
        }
        .frame(width: 275)
        .background(colorScheme == .light ? Color(nsColor: .windowBackgroundColor) : Color.clear)
    }
}
