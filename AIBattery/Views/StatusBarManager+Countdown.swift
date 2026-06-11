import AppKit

// MARK: - Countdown ticker

extension StatusBarManager {
    /// Starts (or re-uses) a repeating timer that updates the menu bar countdown text
    /// every tick. Tick interval adapts: 1s when <60s remain, 10s otherwise.
    /// This keeps the menu bar countdown in sync with the popover's TimelineView.
    func startCountdownTimer(resetDate: Date, button: NSStatusBarButton) {
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

    func stopCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        activeResetDate = nil
    }

    /// 1s ticks when <60s remain (live countdown feel), 10s otherwise (low overhead).
    private func countdownTickInterval(for resetDate: Date) -> TimeInterval {
        let diff = resetDate.timeIntervalSinceNow
        return (diff > 0 && diff < 60) ? 1 : 10
    }

    /// Returns the reset date for countdown display when throttled or any window hits 100%.
    /// Priority: binding reset when throttled, otherwise earliest *future* reset of any
    /// exhausted window. Past dates are filtered out — the window has already reset, so
    /// another (still-future) window's countdown should take over instead of dropping to
    /// a stale percentage.
    ///
    /// Pure and parameterized on `now` so tests can assert handoff behaviour between the
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
}
