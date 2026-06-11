import SwiftUI
import AppKit

// MARK: - Render key

/// Everything that determines the rendered menu-bar image. `updateButton` skips
/// the NSAttributedString+NSImage rebuild when this key is unchanged — during a
/// throttle countdown the ticker fires every 10s but the compact text ("2h 15m")
/// only changes ~once a minute, so ~85% of ticks are redundant allocations.
/// (Decided D15: key-based skip, NOT a combined-image cache.)
struct MenuBarRenderKey: Equatable {
    let text: String
    /// Whole-percent bucket — the star's fill resolution at menu-bar size makes
    /// sub-1% differences invisible, and bucketing keeps float jitter from
    /// defeating the skip.
    let percentBucket: Int
    let color: NSColor
    let isBroken: Bool
    let isSparkle: Bool
    let appearanceName: NSAppearance.Name

    init(text: String, percent: Double, color: NSColor, isBroken: Bool, isSparkle: Bool, appearanceName: NSAppearance.Name) {
        self.text = text
        percentBucket = Int(percent.rounded())
        self.color = color
        self.isBroken = isBroken
        self.isSparkle = isSparkle
        self.appearanceName = appearanceName
    }
}

// MARK: - Button update

extension StatusBarManager {
    func updateButton(_ button: NSStatusBarButton, viewModel: UsageViewModel) {
        let metricMode = resolveMetricMode(viewModel: viewModel)
        let activePercent = viewModel.snapshot?.percent(for: metricMode) ?? 0
        let activeRateLimits = viewModel.snapshot?.rateLimits
        // Delegate the whole menu-bar text/percent/countdown decision to a pure
        // resolver. Pulling it out of this MainActor-isolated method means the wiring
        // (which count gates the multi-account branch, how active and per-account
        // resets compose, single-account fallback) is testable end-to-end. v2.2.0
        // shipped a regression because the gate logic lived inline here and the
        // wiring fix (P2 from codex review) was never covered by a test.
        let showAll = UserDefaults.standard.bool(forKey: UserDefaultsKeys.showAllAccountsInMenuBar)
        let perAccount = viewModel.perAccountRateLimits
        // Same eligible-account filter the fan-out uses (non-pending AND authenticated)
        // via the shared `multiAccountDisplayIDs()`, so the menu-bar `order` can't drift
        // from the fan-out candidate set — e.g. rendering a "—" slot for an account that
        // resolved to a real org ID but is now signed out (which the fan-out skips).
        let order = OAuthManager.shared.multiAccountDisplayIDs()
        // Suppress the throttle alarm while the snapshot is unconfirmed (served from
        // cache — e.g. the instant-paint right after wake). A stale percentage is fine;
        // a stale "limit reached" is a false alarm. The next fresh fetch restores it.
        let confirmed = !viewModel.isShowingCachedData
        let display = MenuBarMultiAccountText.resolveDisplay(
            toggleOn: showAll,
            perAccount: perAccount,
            order: order,
            activeRateLimits: activeRateLimits,
            activePercent: activePercent,
            metricMode: metricMode,
            confirmed: confirmed,
            now: Date(),
            countdownResetDate: Self.countdownResetDate(for:now:)
        )
        let percent = display.percent
        let isExhausted = display.isExhausted
        let displayText = display.text
        let countdownReset = display.countdownReset

        let isDarkMenuBar = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let starColor = resolveStarColor(metricMode: metricMode, percent: percent, isThrottled: isExhausted, isDarkMenuBar: isDarkMenuBar)

        // Recovery-sparkle transition detection keys off CONFIRMED data only — a cached
        // wake-paint must not register as a throttle→recovery transition (which would
        // fire a spurious "recovered" sparkle). On unconfirmed data, preserve the last
        // confirmed throttle state for transition tracking while still updating the icon.
        if confirmed {
            updateSparkleState(isThrottled: isExhausted)
        }
        updateRenderState(percent: percent, color: starColor, isThrottled: confirmed ? isExhausted : currentIsThrottled)

        // Skip the image rebuild when nothing visible changed. Sparkle/appearance are
        // part of the key, so their transitions still render. The countdown timer
        // bookkeeping below MUST still run — it manages timers, not pixels.
        let renderKey = MenuBarRenderKey(
            text: displayText,
            percent: percent,
            color: starColor,
            isBroken: isExhausted,
            isSparkle: isSparkleActive,
            appearanceName: button.effectiveAppearance.name
        )
        if renderKey != lastRenderKey {
            lastRenderKey = renderKey
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
        }

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
            ThemeColors.barNSColor(percent: 100)
        } else if metricMode == .contextHealth {
            ThemeColors.contextHealthNSColor(percent: percent)
        } else {
            ThemeColors.barNSColor(percent: percent, isDarkMenuBar: isDarkMenuBar)
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
}
