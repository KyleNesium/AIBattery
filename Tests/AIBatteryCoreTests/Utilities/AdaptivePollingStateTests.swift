import Testing
import Foundation
@testable import AIBatteryCore

@Suite("AdaptivePollingState")
struct AdaptivePollingStateTests {

    @Test func belowThreshold_returnsBaseInterval() {
        var state = AdaptivePollingState()
        // 2 unchanged cycles (below threshold of 3) — should return base
        let i1 = state.evaluate(dataChanged: false, baseInterval: 30)
        #expect(i1 == 30)
        let i2 = state.evaluate(dataChanged: false, baseInterval: 30)
        #expect(i2 == 30)
    }

    @Test func atThreshold_doublesInterval() {
        var state = AdaptivePollingState()
        _ = state.evaluate(dataChanged: false, baseInterval: 30)
        _ = state.evaluate(dataChanged: false, baseInterval: 30)
        // 3rd unchanged cycle — at threshold, should double
        let interval = state.evaluate(dataChanged: false, baseInterval: 30)
        #expect(interval == 60)
    }

    @Test func progressiveDoubling_escalatesPastThreshold() {
        var state = AdaptivePollingState()
        _ = state.evaluate(dataChanged: false, baseInterval: 30) // cycle 1: 30
        _ = state.evaluate(dataChanged: false, baseInterval: 30) // cycle 2: 30
        let c3 = state.evaluate(dataChanged: false, baseInterval: 30) // cycle 3: 30*2 = 60
        let c4 = state.evaluate(dataChanged: false, baseInterval: 30) // cycle 4: 30*4 = 120
        let c5 = state.evaluate(dataChanged: false, baseInterval: 30) // cycle 5: 30*8 = 240
        let c6 = state.evaluate(dataChanged: false, baseInterval: 30) // cycle 6: 30*16 = 300 (capped)
        #expect(c3 == 60)
        #expect(c4 == 120)
        #expect(c5 == 240)
        #expect(c6 == 300) // capped at max
    }

    @Test func capsAtMax() {
        var state = AdaptivePollingState()
        // Push past threshold with a large base interval
        for _ in 0..<5 {
            _ = state.evaluate(dataChanged: false, baseInterval: 200)
        }
        let interval = state.evaluate(dataChanged: false, baseInterval: 200)
        #expect(interval == AdaptivePollingState.maxPollingInterval)
    }

    @Test func dataChange_resetsCounter() {
        var state = AdaptivePollingState()
        // Build up unchanged cycles
        _ = state.evaluate(dataChanged: false, baseInterval: 30)
        _ = state.evaluate(dataChanged: false, baseInterval: 30)
        #expect(state.unchangedCycles == 2)

        // Data changes — should reset
        let interval = state.evaluate(dataChanged: true, baseInterval: 30)
        #expect(interval == 30)
        #expect(state.unchangedCycles == 0)
    }

    @Test func constants_matchExpected() {
        #expect(AdaptivePollingState.adaptiveThreshold == 3)
        #expect(AdaptivePollingState.maxPollingInterval == 300)
    }

    @Test func freshState_startsAtZero() {
        let state = AdaptivePollingState()
        #expect(state.unchangedCycles == 0)
    }
}
