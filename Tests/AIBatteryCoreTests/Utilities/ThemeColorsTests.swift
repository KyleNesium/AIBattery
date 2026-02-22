import Testing
import SwiftUI
@testable import AIBatteryCore

@Suite("ThemeColors")
struct ThemeColorsTests {

    // MARK: - Bar colors return distinct values per range

    @Test func barColor_allRanges_returnDistinctColors() {
        // Reset colorblind mode for test
        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.colorblindMode)

        let low = ThemeColors.barColor(percent: 25)
        let mid = ThemeColors.barColor(percent: 65)
        let high = ThemeColors.barColor(percent: 85)
        let critical = ThemeColors.barColor(percent: 96)

        // All four should be distinct
        #expect(low != mid)
        #expect(mid != high)
        #expect(high != critical)
    }

    @Test func barColor_colorblind_returnDistinctColors() {
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.colorblindMode)
        defer { UserDefaults.standard.set(false, forKey: UserDefaultsKeys.colorblindMode) }

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
        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.colorblindMode)

        let green = ThemeColors.bandColor(.green)
        let orange = ThemeColors.bandColor(.orange)
        let red = ThemeColors.bandColor(.red)
        let unknown = ThemeColors.bandColor(.unknown)

        #expect(green != orange)
        #expect(orange != red)
        #expect(red != unknown)
    }

    @Test func bandColor_colorblind_allBands_distinct() {
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.colorblindMode)
        defer { UserDefaults.standard.set(false, forKey: UserDefaultsKeys.colorblindMode) }

        let green = ThemeColors.bandColor(.green)
        let orange = ThemeColors.bandColor(.orange)
        let red = ThemeColors.bandColor(.red)

        #expect(green != orange)
        #expect(orange != red)
    }

    // MARK: - Status colors

    @Test func statusColor_operational_notGray() {
        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.colorblindMode)
        let color = ThemeColors.statusColor(.operational)
        #expect(color != .gray)
    }

    @Test func statusColor_majorOutage_notGreen() {
        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.colorblindMode)
        let color = ThemeColors.statusColor(.majorOutage)
        #expect(color != .green)
    }

    @Test func statusColor_colorblind_operational() {
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.colorblindMode)
        defer { UserDefaults.standard.set(false, forKey: UserDefaultsKeys.colorblindMode) }
        let color = ThemeColors.statusColor(.operational)
        #expect(color != .gray)
    }
}
