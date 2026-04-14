import Testing
import SwiftUI
@testable import AIBatteryCore

@Suite("Typography")
struct TypographyTests {
    @Test func sectionHeader_isSubheadlineBold() {
        #expect(Typography.sectionHeader == Font.subheadline.bold())
    }
    @Test func chevronIcon_isSize9Bold() {
        #expect(Typography.chevronIcon == Font.system(size: 9, weight: .bold))
    }
    @Test func heroTitle_isSize14() {
        #expect(Typography.heroTitle == Font.system(size: 14))
    }
    @Test func heroValue_isSize12Bold() {
        #expect(Typography.heroValue == Font.system(size: 12, weight: .bold))
    }
    @Test func bodyLabel_isSize11Medium() {
        #expect(Typography.bodyLabel == Font.system(size: 11, weight: .medium))
    }
    @Test func caption_isCaption() {
        #expect(Typography.caption == Font.caption)
    }
    @Test func tinyLabel_isCaption2() {
        #expect(Typography.tinyLabel == Font.caption2)
    }
    @Test func monoValue_isHeadlineMonoSemibold() {
        #expect(Typography.monoValue == Font.system(.headline, design: .monospaced, weight: .semibold))
    }
    @Test func monoValueMedium_isSubheadlineMonoSemibold() {
        #expect(Typography.monoValueMedium == Font.system(.subheadline, design: .monospaced, weight: .semibold))
    }
    @Test func monoCaption_isCaptionMono() {
        #expect(Typography.monoCaption == Font.system(.caption, design: .monospaced))
    }
    @Test func monoCaptionSmall_isCaption2Mono() {
        #expect(Typography.monoCaptionSmall == Font.system(.caption2, design: .monospaced))
    }
    @Test func monoTiny_isSize10Mono() {
        #expect(Typography.monoTiny == Font.system(size: 10, design: .monospaced))
    }
    @Test func badgeLabel_isSize10MediumMono() {
        #expect(Typography.badgeLabel == Font.system(size: 10, weight: .medium, design: .monospaced))
    }
    @Test func buttonLabel_isSubheadlineMedium() {
        #expect(Typography.buttonLabel == Font.subheadline.weight(.medium))
    }
    @Test func decorativeIcon_meetsMinimumSize() {
        // UI-05: minimum 9pt floor — decorativeIcon aliases iconSmall
        #expect(Typography.decorativeIcon == Font.system(size: 9))
    }
}
