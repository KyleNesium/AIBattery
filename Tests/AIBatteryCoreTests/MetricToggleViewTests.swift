import Testing
@testable import AIBatteryCore

@Suite("MetricToggleView ordering logic")
struct MetricToggleViewTests {

    @Test("MetricMode.allCases contains all 3 modes")
    func allCasesContainsAllModes() {
        let allCases = MetricMode.allCases
        #expect(allCases.count == 3)
        #expect(allCases.contains(.fiveHour))
        #expect(allCases.contains(.sevenDay))
        #expect(allCases.contains(.contextHealth))
    }

    @Test("MetricMode shortLabels are correct")
    func shortLabelsCorrect() {
        #expect(MetricMode.fiveHour.shortLabel == "5 Hour")
        #expect(MetricMode.sevenDay.shortLabel == "7 Day")
        #expect(MetricMode.contextHealth.shortLabel == "Context")
    }

    @Test("recomputeOrderedModes places current mode first",
          arguments: MetricMode.allCases)
    func orderedModesStartsWithCurrent(currentMode: MetricMode) {
        let ordered = recomputeOrderedModes(current: currentMode)
        #expect(ordered.first == currentMode)
        #expect(ordered.count == MetricMode.allCases.count)
        // All modes present
        for mode in MetricMode.allCases {
            #expect(ordered.contains(mode))
        }
        // No duplicates
        #expect(Set(ordered).count == ordered.count)
    }

    @Test("recomputeOrderedModes remaining modes follow in stable order")
    func orderedModesRemainingOrder() {
        let ordered = recomputeOrderedModes(current: .sevenDay)
        #expect(ordered[0] == .sevenDay)
        // Remaining should be in allCases order minus current
        let remaining = Array(ordered.dropFirst())
        let expected = MetricMode.allCases.filter { $0 != .sevenDay }
        #expect(remaining == expected)
    }
}

/// Extracted pure function matching the logic in MetricToggleView.
/// This must be kept in sync with the view's recomputeOrderedModes.
private func recomputeOrderedModes(current: MetricMode) -> [MetricMode] {
    [current] + MetricMode.allCases.filter { $0 != current }
}
