import Testing
@testable import AIBatteryCore

@Suite("DeferredRenderState")
struct DeferredRenderingTests {
    // MARK: - Initial state

    @Test func initialState_hasAppearedIsFalse() {
        let state = DeferredRenderState()
        #expect(state.hasAppeared == false)
    }

    // MARK: - appeared()

    @Test func appeared_setsHasAppearedTrue() {
        var state = DeferredRenderState()
        state.appeared()
        #expect(state.hasAppeared == true)
    }

    // MARK: - disappeared()

    @Test func disappeared_setsHasAppearedFalse() {
        var state = DeferredRenderState()
        state.appeared()
        state.disappeared()
        #expect(state.hasAppeared == false)
    }

    // MARK: - Cycle

    @Test func cycle_appearedThenDisappearedThenAppeared_isTrue() {
        var state = DeferredRenderState()
        state.appeared()
        state.disappeared()
        state.appeared()
        #expect(state.hasAppeared == true)
    }

    // MARK: - Idempotence

    @Test func multipleDisappeared_staysFalse() {
        var state = DeferredRenderState()
        state.disappeared()
        state.disappeared()
        state.disappeared()
        #expect(state.hasAppeared == false)
    }
}
