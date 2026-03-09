import Testing
import Foundation
import AppKit
@testable import AIBatteryCore

@Suite("Keyboard Navigation")
struct KeyboardNavigationTests {

    // MARK: - Key-to-action mapping (pure function tests)

    @Test func escape_closesPanel() {
        let event = makeKeyEvent(keyCode: 53)
        #expect(StatusBarManager.keyAction(for: event) == .close)
    }

    @Test func r_refreshes() {
        let event = makeKeyEvent(keyCode: 15)
        let action = StatusBarManager.keyAction(for: event)
        guard case .refresh = action else {
            Issue.record("Expected .refresh, got \(String(describing: action))")
            return
        }
    }

    @Test func key1_switchesFiveHour() {
        let event = makeKeyEvent(keyCode: 18)
        let action = StatusBarManager.keyAction(for: event)
        guard case .switchMode(.fiveHour) = action else {
            Issue.record("Expected .switchMode(.fiveHour), got \(String(describing: action))")
            return
        }
    }

    @Test func key2_switchesSevenDay() {
        let event = makeKeyEvent(keyCode: 19)
        let action = StatusBarManager.keyAction(for: event)
        guard case .switchMode(.sevenDay) = action else {
            Issue.record("Expected .switchMode(.sevenDay), got \(String(describing: action))")
            return
        }
    }

    @Test func key3_switchesContextHealth() {
        let event = makeKeyEvent(keyCode: 20)
        let action = StatusBarManager.keyAction(for: event)
        guard case .switchMode(.contextHealth) = action else {
            Issue.record("Expected .switchMode(.contextHealth), got \(String(describing: action))")
            return
        }
    }

    @Test func a_togglesAuto() {
        let event = makeKeyEvent(keyCode: 0)
        let action = StatusBarManager.keyAction(for: event)
        guard case .toggleAuto = action else {
            Issue.record("Expected .toggleAuto, got \(String(describing: action))")
            return
        }
    }

    @Test func s_togglesSettings() {
        let event = makeKeyEvent(keyCode: 1)
        let action = StatusBarManager.keyAction(for: event)
        guard case .toggleSettings = action else {
            Issue.record("Expected .toggleSettings, got \(String(describing: action))")
            return
        }
    }

    @Test func q_quits() {
        let event = makeKeyEvent(keyCode: 12)
        let action = StatusBarManager.keyAction(for: event)
        guard case .quit = action else {
            Issue.record("Expected .quit, got \(String(describing: action))")
            return
        }
    }

    @Test func unknownKey_returnsNil() {
        // F1 key — not mapped
        let event = makeKeyEvent(keyCode: 122)
        #expect(StatusBarManager.keyAction(for: event) == nil)
    }

    @Test func unmappedKeys_returnNil() {
        // Test several unmapped key codes
        let unmappedCodes: [UInt16] = [2, 3, 4, 5, 6, 7, 8, 9, 10, 13, 14, 16, 17]
        for code in unmappedCodes {
            let event = makeKeyEvent(keyCode: code)
            #expect(StatusBarManager.keyAction(for: event) == nil, "keyCode \(code) should not be mapped")
        }
    }

    // MARK: - Helpers

    private func makeKeyEvent(keyCode: UInt16) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )!
    }
}
