import Testing
@testable import AIBatteryCore

/// Unit tests for breathTimerShouldRun — the pure gating function extracted from StatusBarManager.
/// Covers PERF-01: breath timer fires only while popover is visible.
@Suite("BreathTimerGating")
struct BreathTimerGatingTests {

    // MARK: - Visibility gate (isShowing = false → always false)

    // Test 1: Not showing, high percent, not throttled, no sparkle → false
    @Test("returns false when not showing, even at high percent")
    func testNotShowingHighPercent() {
        let result = StatusBarManager.breathTimerShouldRun(
            isShowing: false,
            isThrottled: false,
            isSparkleActive: false,
            percent: 96
        )
        #expect(result == false)
    }

    // Test 2: Not showing, sparkle active → false (visibility beats sparkle)
    @Test("returns false when not showing, even with sparkle active")
    func testNotShowingWithSparkle() {
        let result = StatusBarManager.breathTimerShouldRun(
            isShowing: false,
            isThrottled: false,
            isSparkleActive: true,
            percent: 50
        )
        #expect(result == false)
    }

    // Test 3: Not showing, throttled → false
    @Test("returns false when not showing and throttled")
    func testNotShowingThrottled() {
        let result = StatusBarManager.breathTimerShouldRun(
            isShowing: false,
            isThrottled: true,
            isSparkleActive: false,
            percent: 96
        )
        #expect(result == false)
    }

    // MARK: - Throttle gate (isThrottled = true, isShowing = true → always false)

    // Test 4: Showing, throttled, high percent → false (throttle beats visibility)
    @Test("returns false when showing but throttled")
    func testShowingButThrottled() {
        let result = StatusBarManager.breathTimerShouldRun(
            isShowing: true,
            isThrottled: true,
            isSparkleActive: false,
            percent: 96
        )
        #expect(result == false)
    }

    // MARK: - Timer should run (isShowing = true, not throttled)

    // Test 5: Showing, not throttled, percent >= 95, no sparkle → true
    @Test("returns true when showing, not throttled, percent >= 95")
    func testShowingHighPercent() {
        let result = StatusBarManager.breathTimerShouldRun(
            isShowing: true,
            isThrottled: false,
            isSparkleActive: false,
            percent: 96
        )
        #expect(result == true)
    }

    // Test 6: Showing, not throttled, sparkle active, low percent → true
    @Test("returns true when showing, not throttled, sparkle active")
    func testShowingWithSparkle() {
        let result = StatusBarManager.breathTimerShouldRun(
            isShowing: true,
            isThrottled: false,
            isSparkleActive: true,
            percent: 50
        )
        #expect(result == true)
    }

    // MARK: - Timer should stop (isShowing = true, not throttled, low percent, no sparkle)

    // Test 7: Showing, not throttled, low percent, no sparkle → false
    @Test("returns false when showing but low percent and no sparkle")
    func testShowingLowPercent() {
        let result = StatusBarManager.breathTimerShouldRun(
            isShowing: true,
            isThrottled: false,
            isSparkleActive: false,
            percent: 50
        )
        #expect(result == false)
    }
}
