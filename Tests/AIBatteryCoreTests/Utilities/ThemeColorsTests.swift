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

    @Test func chartAccent_standard_isOrange() {
        setColorblind(false)
        #expect(ThemeColors.chartAccent == .orange)
    }

    @Test func chartAccent_colorblind_isBlue() {
        setColorblind(true)
        defer { setColorblind(false) }
        #expect(ThemeColors.chartAccent == .blue)
    }

    @Test func caution_standard_isOrange() {
        setColorblind(false)
        #expect(ThemeColors.caution == .orange)
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
