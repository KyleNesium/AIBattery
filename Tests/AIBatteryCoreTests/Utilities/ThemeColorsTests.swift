import Testing
import SwiftUI
@testable import AIBatteryCore

@Suite("ThemeColors", .serialized)
struct ThemeColorsTests {

    private func setColorblind(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: UserDefaultsKeys.colorblindMode)
        ThemeColors.refreshColorblindFlag()
    }

    // MARK: - Bar colors return distinct values per range

    @Test func barColor_allRanges_returnDistinctColors() {
        setColorblind(false)

        let low = ThemeColors.barColor(percent: 25)
        let mid = ThemeColors.barColor(percent: 65)
        let high = ThemeColors.barColor(percent: 85)
        let critical = ThemeColors.barColor(percent: 96)

        #expect(low != mid)
        #expect(mid != high)
        #expect(high != critical)
    }

    @Test func barColor_colorblind_returnDistinctColors() {
        setColorblind(true)
        defer { setColorblind(false) }

        let low = ThemeColors.barColor(percent: 25)
        let mid = ThemeColors.barColor(percent: 65)
        let high = ThemeColors.barColor(percent: 85)
        let critical = ThemeColors.barColor(percent: 96)

        #expect(low != mid)
        #expect(mid != high)
        #expect(high != critical)
    }

    // MARK: - Band colors

    @Test func bandColor_allBands_returnDistinctColors() {
        setColorblind(false)

        let green = ThemeColors.bandColor(.green)
        let orange = ThemeColors.bandColor(.orange)
        let red = ThemeColors.bandColor(.red)
        let unknown = ThemeColors.bandColor(.unknown)

        #expect(green != orange)
        #expect(orange != red)
        #expect(red != unknown)
    }

    @Test func bandColor_colorblind_allBands_distinct() {
        setColorblind(true)
        defer { setColorblind(false) }

        let green = ThemeColors.bandColor(.green)
        let orange = ThemeColors.bandColor(.orange)
        let red = ThemeColors.bandColor(.red)

        #expect(green != orange)
        #expect(orange != red)
    }

    // MARK: - Status colors

    @Test func statusColor_operational_notGray() {
        setColorblind(false)
        let color = ThemeColors.statusColor(.operational)
        #expect(color != .gray)
    }

    @Test func statusColor_majorOutage_notGreen() {
        setColorblind(false)
        let color = ThemeColors.statusColor(.majorOutage)
        #expect(color != .green)
    }

    @Test func statusColor_colorblind_operational() {
        setColorblind(true)
        defer { setColorblind(false) }
        let color = ThemeColors.statusColor(.operational)
        #expect(color != .gray)
    }

    // MARK: - NSColor variant

    @Test func barNSColor_allRanges_returnDistinctColors() {
        setColorblind(false)

        let low = ThemeColors.barNSColor(percent: 25)
        let mid = ThemeColors.barNSColor(percent: 65)
        let high = ThemeColors.barNSColor(percent: 85)
        let critical = ThemeColors.barNSColor(percent: 96)

        #expect(low != mid)
        #expect(mid != high)
        #expect(high != critical)
    }

    @Test func barNSColor_colorblind_returnDistinctColors() {
        setColorblind(true)
        defer { setColorblind(false) }

        let low = ThemeColors.barNSColor(percent: 25)
        let mid = ThemeColors.barNSColor(percent: 65)
        let high = ThemeColors.barNSColor(percent: 85)
        let critical = ThemeColors.barNSColor(percent: 96)

        #expect(low != mid)
        #expect(mid != high)
        #expect(high != critical)
    }

    // MARK: - Semantic colors

    @Test func chartAccent_standard_notBlue() {
        setColorblind(false)
        #expect(ThemeColors.chartAccent != .blue)
    }

    @Test func chartAccent_colorblind_isBlue() {
        setColorblind(true)
        defer { setColorblind(false) }
        #expect(ThemeColors.chartAccent == .blue)
    }

    @Test func caution_standard_notRed() {
        setColorblind(false)
        #expect(ThemeColors.caution != .red)
    }

    @Test func trendColor_allDirections_distinct() {
        setColorblind(false)
        let up = ThemeColors.trendColor(.up)
        let down = ThemeColors.trendColor(.down)
        let flat = ThemeColors.trendColor(.flat)
        #expect(up != down)
        #expect(up != flat)
    }

    // MARK: - Danger color

    @Test func danger_standard_isRed() {
        setColorblind(false)
        #expect(ThemeColors.danger == .red)
    }

    @Test func danger_colorblind_isPurple() {
        setColorblind(true)
        defer { setColorblind(false) }
        #expect(ThemeColors.danger == .purple)
    }

    @Test func danger_differentFromCaution() {
        setColorblind(false)
        #expect(ThemeColors.danger != ThemeColors.caution)
    }

    @Test func danger_colorblind_differentFromCaution() {
        setColorblind(true)
        defer { setColorblind(false) }
        #expect(ThemeColors.danger != ThemeColors.caution)
    }

    // MARK: - Daily Pace colors

    @Test func dailyPaceColor_allRanges_returnDistinctColors() {
        setColorblind(false)

        let below = ThemeColors.dailyPaceColor(percent: 50)
        let atAvg = ThemeColors.dailyPaceColor(percent: 120)
        let above = ThemeColors.dailyPaceColor(percent: 170)
        let high = ThemeColors.dailyPaceColor(percent: 250)

        #expect(below != atAvg)
        #expect(atAvg != above)
        #expect(above != high)
    }

    @Test func dailyPaceColor_colorblind_returnDistinctColors() {
        setColorblind(true)
        defer { setColorblind(false) }

        let below = ThemeColors.dailyPaceColor(percent: 50)
        let atAvg = ThemeColors.dailyPaceColor(percent: 120)
        let above = ThemeColors.dailyPaceColor(percent: 170)
        let high = ThemeColors.dailyPaceColor(percent: 250)

        #expect(below != atAvg)
        #expect(atAvg != above)
        #expect(above != high)
    }

    @Test func dailyPaceNSColor_allRanges_returnDistinctColors() {
        setColorblind(false)

        let below = ThemeColors.dailyPaceNSColor(percent: 50)
        let atAvg = ThemeColors.dailyPaceNSColor(percent: 120)
        let above = ThemeColors.dailyPaceNSColor(percent: 170)
        let high = ThemeColors.dailyPaceNSColor(percent: 250)

        #expect(below != atAvg)
        #expect(atAvg != above)
        #expect(above != high)
    }

    @Test func dailyPaceColor_boundaries() {
        setColorblind(false)
        // Just below and at each threshold
        let at99 = ThemeColors.dailyPaceColor(percent: 99)
        let at100 = ThemeColors.dailyPaceColor(percent: 100)
        let at149 = ThemeColors.dailyPaceColor(percent: 149)
        let at150 = ThemeColors.dailyPaceColor(percent: 150)
        let at199 = ThemeColors.dailyPaceColor(percent: 199)
        let at200 = ThemeColors.dailyPaceColor(percent: 200)

        #expect(at99 != at100)
        #expect(at149 != at150)
        #expect(at199 != at200)
    }

    // MARK: - Boundary values

    @Test func barColor_exactBoundaries() {
        setColorblind(false)
        // Test exact boundary values
        let at0 = ThemeColors.barColor(percent: 0)
        let at50 = ThemeColors.barColor(percent: 50)
        let at80 = ThemeColors.barColor(percent: 80)
        let at95 = ThemeColors.barColor(percent: 95)
        // 0 is in green range, 50 starts yellow, 80 starts orange, 95 starts red
        #expect(at0 != at50)
        #expect(at50 != at80)
        #expect(at80 != at95)
    }
}
