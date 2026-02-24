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
