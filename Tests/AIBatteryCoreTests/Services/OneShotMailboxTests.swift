import Testing
@testable import AIBatteryCore

/// Plan 1 review F10: the Codex callback server starts listening in `begin()` before
/// the UI awaits the result. A redirect that arrives in that gap must be buffered,
/// not dropped (a dropped callback left the sign-in spinner hanging until the 180 s
/// timeout).
@Suite("OneShotMailbox")
@MainActor
struct OneShotMailboxTests {
    @Test func deliverBeforeAwait_isBuffered() async {
        let box = OneShotMailbox<Int>()
        #expect(box.deliver(42))
        let value = await box.value()
        #expect(value == 42)
    }

    @Test func awaitBeforeDeliver_resumesOnDelivery() async {
        let box = OneShotMailbox<String>()
        Task { @MainActor in
            await Task.yield()
            _ = box.deliver("late")
        }
        let value = await box.value()
        #expect(value == "late")
    }

    @Test func secondDelivery_isIgnored() async {
        let box = OneShotMailbox<Int>()
        #expect(box.deliver(1))
        #expect(!box.deliver(2))
        let value = await box.value()
        #expect(value == 1)
    }
}
