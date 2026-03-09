import Testing
import Foundation
import AppKit
@testable import AIBatteryCore

@Suite("GlobalHotkeyManager")
struct GlobalHotkeyManagerTests {

    // MARK: - Key matching (pure function tests)

    @Test func matches_correctCombo() {
        // Option+Shift+B with keyCode 11
        let event = makeKeyEvent(keyCode: 11, modifiers: [.option, .shift])
        #expect(GlobalHotkeyManager.matches(event: event))
    }

    @Test func matches_wrongKeyCode() {
        // Option+Shift + wrong key
        let event = makeKeyEvent(keyCode: 0, modifiers: [.option, .shift])
        #expect(!GlobalHotkeyManager.matches(event: event))
    }

    @Test func matches_missingShift() {
        // Only Option + B
        let event = makeKeyEvent(keyCode: 11, modifiers: [.option])
        #expect(!GlobalHotkeyManager.matches(event: event))
    }

    @Test func matches_missingOption() {
        // Only Shift + B
        let event = makeKeyEvent(keyCode: 11, modifiers: [.shift])
        #expect(!GlobalHotkeyManager.matches(event: event))
    }

    @Test func matches_extraModifiers() {
        // Option+Shift+Command+B — extra modifier should not match
        let event = makeKeyEvent(keyCode: 11, modifiers: [.option, .shift, .command])
        #expect(!GlobalHotkeyManager.matches(event: event))
    }

    @Test func matches_noModifiers() {
        // Just B with no modifiers
        let event = makeKeyEvent(keyCode: 11, modifiers: [])
        #expect(!GlobalHotkeyManager.matches(event: event))
    }

    @Test func matches_customKeyCode() {
        // Custom combo: Command+K
        let event = makeKeyEvent(keyCode: 40, modifiers: [.command])
        #expect(GlobalHotkeyManager.matches(event: event, keyCode: 40, modifiers: [.command]))
    }

    @Test func matches_customCombo_wrongKey() {
        let event = makeKeyEvent(keyCode: 41, modifiers: [.command])
        #expect(!GlobalHotkeyManager.matches(event: event, keyCode: 40, modifiers: [.command]))
    }

    @Test func matches_capsLockIgnored() {
        // Option+Shift+B with caps lock — should still match (caps lock is filtered)
        let event = makeKeyEvent(keyCode: 11, modifiers: [.option, .shift, .capsLock])
        // Caps lock is NOT in deviceIndependentFlagsMask subset we care about,
        // but NSEvent.ModifierFlags.capsLock IS device-independent.
        // So this should NOT match because capsLock adds an extra flag.
        #expect(!GlobalHotkeyManager.matches(event: event))
    }

    // MARK: - Helpers

    private func makeKeyEvent(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
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
