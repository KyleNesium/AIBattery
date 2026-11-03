import Testing
@testable import AIBatteryCore

@Suite("AlertThreshold")
struct AlertThresholdTests {
    @Test func steps_areTheFourStopsOnTheSlider() {
        #expect(AlertThreshold.steps == [60, 70, 80, 90])
    }

    @Test func steps_ascendInTens() {
        let gaps = zip(AlertThreshold.steps, AlertThreshold.steps.dropFirst()).map { $1 - $0 }
        #expect(gaps.allSatisfy { $0 == 10 })
    }

    @Test func labels_trackTheSteps() {
        #expect(AlertThreshold.labels == ["60%", "70%", "80%", "90%"])
    }

    @Test func defaultThreshold_isAStop() {
        #expect(AlertThreshold.steps.contains(AlertThreshold.default))
    }

    @Test func snapped_leavesAStopAlone() {
        for step in AlertThreshold.steps {
            #expect(AlertThreshold.snapped(step) == step)
        }
    }

    @Test func snapped_pullsTheOldTopStopDownToNinety() {
        #expect(AlertThreshold.snapped(95) == 90)
    }

    /// A value sitting exactly between two stops goes to the lower one, so the snap can
    /// only ever make an alert fire earlier than it used to — never later, which would
    /// quietly cost someone the warning they had configured.
    @Test func snapped_breaksATieTowardsTheEarlierAlert() {
        #expect(AlertThreshold.snapped(85) == 80)
        #expect(AlertThreshold.snapped(75) == 70)
        #expect(AlertThreshold.snapped(65) == 60)
    }

    @Test func snapped_pullsTheOldLowStopsUpToSixty() {
        #expect(AlertThreshold.snapped(50) == 60)
        #expect(AlertThreshold.snapped(55) == 60)
    }

    @Test func snapped_roundsToTheNearerStop() {
        #expect(AlertThreshold.snapped(74) == 70)
        #expect(AlertThreshold.snapped(76) == 80)
    }

    @Test func snapped_treatsAnUnsetValueAsTheDefault() {
        #expect(AlertThreshold.snapped(0) == AlertThreshold.default)
        #expect(AlertThreshold.snapped(-5) == AlertThreshold.default)
    }

    @Test func snapped_clampsAboveTheTopStop() {
        #expect(AlertThreshold.snapped(100) == 90)
    }

    @Test func snapped_alwaysLandsOnAStop() {
        for raw in stride(from: 1.0, through: 100.0, by: 1.0) {
            #expect(AlertThreshold.steps.contains(AlertThreshold.snapped(raw)))
        }
    }
}
