import Testing
import SwiftUI
@testable import AIBatteryCore

@Suite("GaugeBar")
struct GaugeBarTests {

    // MARK: - Clamping logic

    @Test func clampPercent_belowZero_returnsZero() {
        let clamped = GaugeBar.clampedPercent(-10)
        #expect(clamped == 0.0)
    }

    @Test func clampPercent_zero_returnsZero() {
        let clamped = GaugeBar.clampedPercent(0)
        #expect(clamped == 0.0)
    }

    @Test func clampPercent_fifty_returnsFifty() {
        let clamped = GaugeBar.clampedPercent(50)
        #expect(clamped == 0.5)
    }

    @Test func clampPercent_hundred_returnsOne() {
        let clamped = GaugeBar.clampedPercent(100)
        #expect(clamped == 1.0)
    }

    @Test func clampPercent_overHundred_clampsToOne() {
        let clamped = GaugeBar.clampedPercent(150)
        #expect(clamped == 1.0)
    }

    // MARK: - View construction

    @Test func body_buildsWithoutCrash_zeroPercent() {
        let view = GaugeBar(percent: 0, barColor: .green)
        _ = view.body
    }

    @Test func body_buildsWithoutCrash_fiftyPercent() {
        let view = GaugeBar(percent: 50, barColor: .blue)
        _ = view.body
    }

    @Test func body_buildsWithoutCrash_hundredPercent() {
        let view = GaugeBar(percent: 100, barColor: .red)
        _ = view.body
    }

    @Test func body_buildsWithoutCrash_overHundredPercent() {
        let view = GaugeBar(percent: 150, barColor: .red)
        _ = view.body
    }

    @Test func body_buildsWithoutCrash_negativePercent() {
        let view = GaugeBar(percent: -10, barColor: .blue)
        _ = view.body
    }
}
