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

    // MARK: - isDarkMenuBar gold override

    @Test func barNSColor_lightMenuBar_usesGoldInMidBand() {
        setColorblind(false)
        let color = ThemeColors.barNSColor(percent: 65, isDarkMenuBar: false)
        #expect(color == ThemeColors.menuBarGold)
    }

    @Test func barNSColor_darkMenuBar_usesSystemYellowInMidBand() {
        setColorblind(false)
        let color = ThemeColors.barNSColor(percent: 65, isDarkMenuBar: true)
        #expect(color == .systemYellow)
    }

    @Test func barNSColor_nilMenuBar_usesSystemYellowInMidBand() {
        setColorblind(false)
        let color = ThemeColors.barNSColor(percent: 65)
        #expect(color == .systemYellow)
    }

    @Test func barNSColor_colorblind_lightMenuBar_usesGoldInMidBand() {
        setColorblind(true)
        defer { setColorblind(false) }
        let color = ThemeColors.barNSColor(percent: 65, isDarkMenuBar: false)
        #expect(color == ThemeColors.menuBarGold)
    }

    @Test func barNSColor_colorblind_darkMenuBar_usesSystemTealInMidBand() {
        setColorblind(true)
        defer { setColorblind(false) }
        let color = ThemeColors.barNSColor(percent: 65, isDarkMenuBar: true)
        #expect(color == .systemTeal)
    }

    @Test func barNSColor_lightMenuBar_outsideMidBand_ignoresFlag() {
        setColorblind(false)
        // Low band still green, critical band still red — isDarkMenuBar only affects 50-80
        let low = ThemeColors.barNSColor(percent: 25, isDarkMenuBar: false)
        let critical = ThemeColors.barNSColor(percent: 96, isDarkMenuBar: false)
        #expect(low == .systemGreen)
        #expect(critical == .systemRed)
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

    // MARK: - Context health color (moved from MenuBarIconTests to avoid races)

    @Test func contextHealthNSColor_matchesHealthBandThresholds() {
        setColorblind(false)
        let green = ThemeColors.contextHealthNSColor(percent: 50)
        let orange = ThemeColors.contextHealthNSColor(percent: 70)
        let red = ThemeColors.contextHealthNSColor(percent: 85)
        #expect(green != orange)
        #expect(orange != red)
        #expect(green == .systemGreen)
        #expect(red == .systemRed)
    }

    // MARK: - v2.3.1 semantic-stroke tokens

    @Test func inactiveStroke_isSecondary() {
        // Pin: ThemeColors.inactiveStroke must resolve to .secondary so that
        // MetricToggleView's unselected ring and TutorialOverlay's inactive
        // step dots stay tied to system secondary tinting.
        #expect(ThemeColors.inactiveStroke == .secondary)
    }

    @Test func shadowColor_isBlack() {
        // Pin: ThemeColors.shadowColor must stay .black — MetricToggleView's
        // selected-tab shadow and TutorialOverlay's backdrop both opacity-mix
        // off this token, and the visual result is calibrated against pure black.
        #expect(ThemeColors.shadowColor == .black)
    }
}
