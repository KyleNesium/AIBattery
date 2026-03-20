import Testing
@testable import AIBatteryCore

/// Unit tests for pure guard/debounce functions in StatusBarManager.
/// Covers REL-01: guard window suppresses spurious deactivation events,
/// and debounce prevents double-click toggle races.
@Suite("ReliabilityGuard")
struct ReliabilityGuardTests {

    // MARK: - shouldSuppressDeactivation

    @Test("no recent show: distantPast always returns false")
    func testNoRecentShow() {
        #expect(shouldSuppressDeactivation(showedAt: .distantPast, now: Date()) == false)
    }

    @Test("50ms after show: within 200ms guard window — suppress")
    func testWithinGuardAt50ms() {
        let now = Date()
        let showedAt = now
        let deactivationArrival = now.addingTimeInterval(0.05)
        #expect(shouldSuppressDeactivation(showedAt: showedAt, now: deactivationArrival) == true)
    }

    @Test("190ms after show: within 200ms guard window — suppress")
    func testWithinGuardAt190ms() {
        let now = Date()
        let showedAt = now
        let deactivationArrival = now.addingTimeInterval(0.19)
        #expect(shouldSuppressDeactivation(showedAt: showedAt, now: deactivationArrival) == true)
    }

    @Test("200ms after show: exactly at guard window boundary — suppress")
    func testAtGuardBoundary200ms() {
        let now = Date()
        let showedAt = now
        let deactivationArrival = now.addingTimeInterval(0.2)
        #expect(shouldSuppressDeactivation(showedAt: showedAt, now: deactivationArrival) == true)
    }

    @Test("210ms after show: outside 200ms guard window — allow dismiss")
    func testOutsideGuardAt210ms() {
        let now = Date()
        let showedAt = now
        let deactivationArrival = now.addingTimeInterval(0.21)
        #expect(shouldSuppressDeactivation(showedAt: showedAt, now: deactivationArrival) == false)
    }

    @Test("500ms after show: well outside guard window — allow dismiss")
    func testOutsideGuardAt500ms() {
        let now = Date()
        let showedAt = now
        let deactivationArrival = now.addingTimeInterval(0.5)
        #expect(shouldSuppressDeactivation(showedAt: showedAt, now: deactivationArrival) == false)
    }

    // MARK: - shouldDebounceClick

    @Test("no prior click: distantPast always returns false")
    func testNoPriorClick() {
        #expect(shouldDebounceClick(lastClickAt: .distantPast, now: Date()) == false)
    }

    @Test("50ms after last click: within 150ms cooldown — debounce")
    func testWithinCooldownAt50ms() {
        let now = Date()
        let lastClick = now
        let nextClick = now.addingTimeInterval(0.05)
        #expect(shouldDebounceClick(lastClickAt: lastClick, now: nextClick) == true)
    }

    @Test("140ms after last click: within 150ms cooldown — debounce")
    func testWithinCooldownAt140ms() {
        let now = Date()
        let lastClick = now
        let nextClick = now.addingTimeInterval(0.14)
        #expect(shouldDebounceClick(lastClickAt: lastClick, now: nextClick) == true)
    }

    @Test("150ms after last click: exactly at cooldown boundary — debounce")
    func testAtCooldownBoundary150ms() {
        let now = Date()
        let lastClick = now
        let nextClick = now.addingTimeInterval(0.15)
        #expect(shouldDebounceClick(lastClickAt: lastClick, now: nextClick) == true)
    }

    @Test("160ms after last click: outside 150ms cooldown — allow click")
    func testOutsideCooldownAt160ms() {
        let now = Date()
        let lastClick = now
        let nextClick = now.addingTimeInterval(0.16)
        #expect(shouldDebounceClick(lastClickAt: lastClick, now: nextClick) == false)
    }
}
