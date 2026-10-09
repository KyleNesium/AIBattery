import Testing
import AppKit
@testable import AIBatteryCore

@Suite("MenuBarIcon")
@MainActor
struct MenuBarIconTests {
    private let testColor: NSColor = .systemGreen

    // MARK: - Quantized percent

    @Test func quantizedPercent_roundsDown() {
        #expect(MenuBarIcon.quantizedPercent(0) == 0)
        #expect(MenuBarIcon.quantizedPercent(4.9) == 0)
        #expect(MenuBarIcon.quantizedPercent(5) == 5)
        #expect(MenuBarIcon.quantizedPercent(7.5) == 5)
        #expect(MenuBarIcon.quantizedPercent(50) == 50)
        #expect(MenuBarIcon.quantizedPercent(99) == 95)
        #expect(MenuBarIcon.quantizedPercent(100) == 100)
    }

    @Test func quantizedPercent_clampsOutOfRange() {
        #expect(MenuBarIcon.quantizedPercent(-5) == 0)
        #expect(MenuBarIcon.quantizedPercent(150) == 100)
    }

    // MARK: - Provider marks in the menu bar text

    /// The multi-account text model keeps the ✦ / ⬡ glyphs (they are what the tests
    /// and the render key compare); at draw time each glyph becomes an inline brand
    /// mark image (NSTextAttachment), never a rendered text character.
    @Test func menuBarAttributedText_replacesGlyphsWithMarkAttachments() {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let text = "\(AIProvider.claude.glyph)\u{00A0}42%  \(AIProvider.codex.glyph)\u{00A0}7%"
        let attributed = MenuBarIcon.menuBarAttributedText(text, font: font, color: .white)
        let string = attributed.string
        #expect(!string.contains(AIProvider.claude.glyph))
        #expect(!string.contains(AIProvider.codex.glyph))
        // Object-replacement characters stand where the glyphs were; the rest is untouched.
        #expect(string == "\u{FFFC}\u{00A0}42%  \u{FFFC}\u{00A0}7%")
        var attachments = 0
        attributed.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
            if value is NSTextAttachment {
                attachments += 1
            }
        }
        #expect(attachments == 2)
    }

    @Test func menuBarAttributedText_plainTextHasNoAttachments() {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let attributed = MenuBarIcon.menuBarAttributedText("42%\u{00A0}|\u{00A0}23%", font: font, color: .white)
        #expect(attributed.string == "42%\u{00A0}|\u{00A0}23%")
        #expect(attributed.attribute(.attachment, at: 0, effectiveRange: nil) == nil)
    }

    /// The real status-item image: mixed-provider text with inline brand marks must
    /// render (no empty / zero-size image) and be wider than a single-provider string
    /// of the same digits — the marks occupy real width, they are not dropped.
    @Test func combinedStatusBarImage_rendersMixedProviderTextWithMarks() {
        let mixed = "\(AIProvider.claude.glyph)\u{00A0}42%  \(AIProvider.codex.glyph)\u{00A0}7%"
        let plain = "42%\u{00A0}|\u{00A0}7%"
        let mixedImage = MenuBarIcon.combinedStatusBarImage(text: mixed, percent: 42, color: testColor, menuBarAppearance: NSAppearance(named: .darkAqua))
        let plainImage = MenuBarIcon.combinedStatusBarImage(text: plain, percent: 42, color: testColor, menuBarAppearance: NSAppearance(named: .aqua))
        #expect(mixedImage.size.height > 0)
        #expect(mixedImage.size.width > plainImage.size.width)
        #expect(mixedImage.cgImage(forProposedRect: nil, context: nil, hints: nil) != nil)
        #expect(plainImage.cgImage(forProposedRect: nil, context: nil, hints: nil) != nil)
    }

    /// VoiceOver reads provider names, not symbol names.
    @Test func spokenMenuBarText_namesProviders() {
        let text = "\(AIProvider.claude.glyph)\u{00A0}42%  \(AIProvider.codex.glyph)\u{00A0}7%"
        #expect(MenuBarIcon.spokenMenuBarText(text) == "Claude\u{00A0}42%  Codex\u{00A0}7%")
        #expect(MenuBarIcon.spokenMenuBarText("42%") == "42%")
    }

    // MARK: - Cache key

    @Test func cacheKey_normalDistinctFromBroken() {
        let normalKey = MenuBarIcon.cacheKey(quantizedPercent: 50, colorHash: 0, isBroken: false, isSparkle: false)
        let brokenKey = MenuBarIcon.cacheKey(quantizedPercent: 50, colorHash: 0, isBroken: true, isSparkle: false)
        #expect(normalKey != brokenKey)
    }

    @Test func cacheKey_differentPercentsAreDistinct() {
        let key0 = MenuBarIcon.cacheKey(quantizedPercent: 0, colorHash: 0, isBroken: false, isSparkle: false)
        let key50 = MenuBarIcon.cacheKey(quantizedPercent: 50, colorHash: 0, isBroken: false, isSparkle: false)
        #expect(key0 != key50)
    }

    @Test func cacheKey_noCollisionAt100Percent() {
        // 100% normal and broken must not collide (was a bug with *10 + 1000 base)
        let normalKey = MenuBarIcon.cacheKey(quantizedPercent: 100, colorHash: 0, isBroken: false, isSparkle: false)
        let brokenKey = MenuBarIcon.cacheKey(quantizedPercent: 100, colorHash: 0, isBroken: true, isSparkle: false)
        #expect(normalKey != brokenKey)
    }

    @Test func cacheKey_sparkleDistinctFromNormalAndBroken() {
        let normalKey = MenuBarIcon.cacheKey(quantizedPercent: 0, colorHash: 0, isBroken: false, isSparkle: false)
        let brokenKey = MenuBarIcon.cacheKey(quantizedPercent: 0, colorHash: 0, isBroken: true, isSparkle: false)
        let sparkleKey = MenuBarIcon.cacheKey(quantizedPercent: 0, colorHash: 0, isBroken: false, isSparkle: true)
        #expect(normalKey != sparkleKey)
        #expect(brokenKey != sparkleKey)
    }

    @Test func cacheKey_differentColorsAreDistinct() {
        let greenKey = MenuBarIcon.cacheKey(quantizedPercent: 75, colorHash: 42, isBroken: false, isSparkle: false)
        let orangeKey = MenuBarIcon.cacheKey(quantizedPercent: 75, colorHash: 99, isBroken: false, isSparkle: false)
        #expect(greenKey != orangeKey)
    }

    // MARK: - Star geometry

    @Test func starPath_has8Vertices() {
        let path = MenuBarIcon.starPath(
            center: NSPoint(x: 8, y: 8),
            outerRadius: 6.5,
            innerRadius: 2.0
        )
        // 1 move + 7 lines + 1 close = 9 elements (macOS 14+: close may add implicit lineTo = 10)
        #expect(path.elementCount >= 9)
        #expect(!path.isEmpty)
    }

    // MARK: - NSBezierPath CGPath conversion

    @Test func asCGPath_convertsCorrectly() {
        let bezier = NSBezierPath()
        bezier.move(to: NSPoint(x: 0, y: 0))
        bezier.line(to: NSPoint(x: 10, y: 0))
        bezier.line(to: NSPoint(x: 5, y: 10))
        bezier.close()
        let cg = bezier.asCGPath
        #expect(!cg.isEmpty)
        #expect(cg.boundingBox.width > 0)
    }

    // MARK: - Rendered icon properties

    @Test func normalIcon_isCorrectSizeNonTemplate() {
        let icon = MenuBarIcon.statusBarImage(for: 50, color: testColor)
        #expect(icon.size.width == MenuBarIcon.iconSize)
        #expect(icon.size.height == MenuBarIcon.iconSize)
        #expect(icon.isTemplate == false)
    }

    @Test func brokenIcon_isCorrectSizeNonTemplate() {
        let icon = MenuBarIcon.statusBarImage(for: 100, color: .systemRed, isBroken: true)
        #expect(icon.size.width == MenuBarIcon.iconSize)
        #expect(icon.size.height == MenuBarIcon.iconSize)
        #expect(icon.isTemplate == false)
    }

    @Test func sameInputs_returnSameCachedInstance() {
        let first = MenuBarIcon.statusBarImage(for: 50, color: testColor)
        let second = MenuBarIcon.statusBarImage(for: 50, color: testColor)
        #expect(first === second)
    }

    @Test func distinctStates_produceDistinctCachedInstances() {
        let normal = MenuBarIcon.statusBarImage(for: 50, color: testColor)
        let broken = MenuBarIcon.statusBarImage(for: 50, color: testColor, isBroken: true)
        let sparkle = MenuBarIcon.statusBarImage(for: 50, color: testColor, isSparkle: true)
        #expect(normal !== broken)
        #expect(normal !== sparkle)
        #expect(broken !== sparkle)
    }

    // MARK: - Sparkle icon (recovery effect)

    @Test func sparkleIcon_isCorrectSizeNonTemplate() {
        let icon = MenuBarIcon.statusBarImage(for: 10, color: .systemGreen, isSparkle: true)
        #expect(icon.size.width == MenuBarIcon.iconSize)
        #expect(icon.size.height == MenuBarIcon.iconSize)
        #expect(icon.isTemplate == false)
    }

    // Note: test for `ThemeColors.contextHealthNSColor` with specific color assertions
    // lives in ThemeColorsTests — that suite is `.serialized` and controls the global
    // `isColorblind` flag deterministically. Asserting here races with the parallel
    // ThemeColors suite and produces flaky Blue/Purple reads from the colorblind palette.
}
