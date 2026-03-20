import Testing
@testable import AIBatteryCore

/// Unit tests for PanelToggleState — the extracted toggle state machine from StatusBarManager.
/// Covers RESP-03: toggle desync prevention.
@Suite("PanelToggleState")
struct StatusBarToggleTests {

    // Test 1: Initial state is not showing
    @Test("starts with isShowing = false")
    func testInitialStateIsFalse() {
        let state = PanelToggleState()
        #expect(state.isShowing == false)
    }

    // Test 2: show() sets isShowing to true
    @Test("show() sets isShowing to true")
    func testShowSetsIsShowingTrue() {
        var state = PanelToggleState()
        state.show()
        #expect(state.isShowing == true)
    }

    // Test 3: dismiss() sets isShowing to false
    @Test("dismiss() sets isShowing to false")
    func testDismissSetsIsShowingFalse() {
        var state = PanelToggleState()
        state.show()
        state.dismiss()
        #expect(state.isShowing == false)
    }

    // Test 4: dismiss() when already false remains false (idempotent)
    @Test("dismiss() when already false stays false")
    func testDismissIsIdempotentWhenFalse() {
        var state = PanelToggleState()
        state.dismiss()
        #expect(state.isShowing == false)
    }

    // Test 5: show → dismiss → show results in isShowing = true (no stuck state)
    @Test("show → dismiss → show results in isShowing = true")
    func testShowDismissShowSequence() {
        var state = PanelToggleState()
        state.show()
        state.dismiss()
        state.show()
        #expect(state.isShowing == true)
    }

    // Test 6: Two consecutive dismiss() calls do not crash or produce incorrect state
    @Test("two consecutive dismiss() calls remain correct")
    func testConsecutiveDismissCallsAreStable() {
        var state = PanelToggleState()
        state.show()
        state.dismiss()
        state.dismiss()
        #expect(state.isShowing == false)
    }

    // Test 7: toggle() from false returns .show and sets isShowing = true
    @Test("toggle() from false returns .show")
    func testToggleFromFalseReturnsShow() {
        var state = PanelToggleState()
        let action = state.toggle()
        #expect(action == .show)
        #expect(state.isShowing == true)
    }

    // Test 8: toggle() from true returns .hide and sets isShowing = false
    @Test("toggle() from true returns .hide")
    func testToggleFromTrueReturnsHide() {
        var state = PanelToggleState()
        state.show()
        let action = state.toggle()
        #expect(action == .hide)
        #expect(state.isShowing == false)
    }
}
