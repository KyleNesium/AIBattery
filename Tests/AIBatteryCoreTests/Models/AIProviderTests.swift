import AppKit
import Foundation
import Testing
@testable import AIBatteryCore

@Suite("AIProvider")
struct AIProviderTests {
    @Test func glyphsAndLabels() {
        #expect(AIProvider.claude.glyph == "\u{2726}") // ✦
        #expect(AIProvider.codex.glyph == "\u{2B21}") // ⬡
        #expect(AIProvider.claude.displayName == "Claude")
        #expect(AIProvider.codex.displayName == "Codex")
        #expect(AIProvider.claude.secondaryWindowLabel == "7-Day")
        #expect(AIProvider.codex.secondaryWindowLabel == "Weekly")
        #expect(AIProvider.claude.secondaryWindowShortCode == "7D")
        #expect(AIProvider.codex.secondaryWindowShortCode == "WK")
        // SF Symbol for SwiftUI surfaces (the text glyph is for the menu-bar string only).
        #expect(AIProvider.claude.symbolName == "sparkle")
        #expect(AIProvider.codex.symbolName == "hexagon")
    }

    /// The header badge draws the real brand marks (Simple Icons, CC0) bundled as
    /// SVG resources; the SF symbol is only a fallback if a resource is missing.
    @Test func brandMarks_areBundledAndLoadable() {
        for provider in AIProvider.allCases {
            let url = AIProvider.markURL(for: provider)
            #expect(url != nil, "missing \(provider.markResourceName).svg")
            #expect(provider.markImage != nil, "unloadable mark for \(provider)")
        }
        #expect(AIProvider.claude.markResourceName == "claude")
        #expect(AIProvider.codex.markResourceName == "openai")
    }

    /// `Bundle.module` is deliberately NOT used: SwiftPM's generated accessor only
    /// looks in the app's root and at an absolute path on the build machine, then
    /// traps — a shipped .app (resources in Contents/Resources) would crash on the
    /// first badge. The resolver walks explicit roots and returns nil instead.
    @Test func markURL_resolvesFromAnExplicitRoot_andNeverTraps() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("aib-marks-\(UUID().uuidString)")
        let resources = root.appendingPathComponent(AIProvider.resourceBundleName).appendingPathComponent("Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("<svg/>".utf8).write(to: resources.appendingPathComponent("claude.svg"))

        // A root without the bundle is skipped; the one with it wins.
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("aib-empty-\(UUID().uuidString)")
        let found = AIProvider.markURL(for: .claude, searchRoots: [empty, root])
        #expect(found?.lastPathComponent == "claude.svg")
        #expect(found?.path.hasPrefix(root.path) == true)

        // Missing file / no usable root → nil, never a trap (SF-symbol fallback).
        #expect(AIProvider.markURL(for: .codex, searchRoots: [empty, root]) == nil)
        #expect(AIProvider.markURL(for: .claude, searchRoots: []) == nil)
        #expect(AIProvider.resourceBundleName == "AIBattery_AIBatteryCore.bundle")
    }

    @Test func accountRecord_decodesLegacyJSONWithoutProvider() throws {
        // Exactly what v2.6.1 persisted — no `provider` key.
        let legacy = Data("""
        [{"id":"org-abc","displayName":"Kyle","billingType":"pro","addedAt":1234567}]
        """.utf8)
        let decoded = try JSONDecoder().decode([AccountRecord].self, from: legacy)
        #expect(decoded[0].provider == .claude)
        #expect(decoded[0].id == "org-abc")
    }

    @Test func accountRecord_roundTripsCodexProvider() throws {
        let record = AccountRecord(id: "uuid-1", displayName: nil, billingType: "team", addedAt: Date(), provider: .codex)
        let data = try JSONEncoder().encode(record)
        let back = try JSONDecoder().decode(AccountRecord.self, from: data)
        #expect(back.provider == .codex)
    }

    /// The mark is decoded once per provider and handed out as a template image, so
    /// SwiftUI / AppKit tint it to the badge or text colour instead of drawing the
    /// SVG's own black fill.
    @MainActor @Test func markImage_isACachedTemplate() {
        for provider in AIProvider.allCases {
            let first = provider.markImage
            let second = provider.markImage
            #expect(first?.isTemplate == true, "\(provider) mark is not a template")
            #expect(first === second, "\(provider) mark decoded twice")
            #expect((first?.size.width ?? 0) > 0 && (first?.size.height ?? 0) > 0)
        }
    }

    /// `NSImage.tinted` is what the drawn menu-bar image uses (an NSTextAttachment can't
    /// tint a template itself): the copy has the requested size, is flat (not a
    /// template), and every opaque source pixel takes the tint colour.
    @MainActor @Test func tinted_fillsOpaquePixelsWithTheColorAtTheRequestedSize() throws {
        let source = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.black.set()
            rect.fill()
            return true
        }
        let tinted = source.tinted(NSColor(red: 1, green: 0, blue: 0, alpha: 1), size: NSSize(width: 8, height: 6))
        #expect(tinted.size == NSSize(width: 8, height: 6))
        #expect(!tinted.isTemplate)

        let cg = try #require(tinted.cgImage(forProposedRect: nil, context: nil, hints: nil))
        // Raw bytes, not `colorAt` — creating NSColors here while other suites touch
        // dynamic system colours off-main deadlocks the parallel run (AppKit colour-cache lock).
        let (r, g, b, a) = try Self.rgba(cg, x: cg.width / 2, y: cg.height / 2)
        // Colour spaces differ between the tint and the bitmap, so compare with a
        // tolerance: black source pixels must come out clearly red, fully opaque.
        #expect(r > 0.85)
        #expect(g < 0.4)
        #expect(b < 0.4)
        #expect(a > 0.95)
    }

    /// Straight (un-premultiplied) RGBA of one pixel, read from the raw bitmap bytes.
    private static func rgba(_ image: CGImage, x: Int, y: Int) throws -> (Double, Double, Double, Double) {
        // Redraw into a context whose byte layout we choose (RGBA8, premultiplied,
        // big-endian) instead of guessing the source image's native layout.
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ))
        // Map the requested pixel (top-left origin) onto the 1×1 context: CG's origin is
        // bottom-left, so flip y.
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        let a = Double(pixel[3]) / 255
        guard a > 0 else { return (0, 0, 0, 0) }
        return (Double(pixel[0]) / 255 / a, Double(pixel[1]) / 255 / a, Double(pixel[2]) / 255 / a, a)
    }

    /// Tinting a real brand mark keeps it inside the box and visible — the menu bar
    /// would otherwise show an empty attachment slot.
    @MainActor @Test func tinted_brandMarkHasVisiblePixels() throws {
        let mark = try #require(AIProvider.claude.markImage)
        let tinted = mark.tinted(.white, size: NSSize(width: 9, height: 9))
        let cg = try #require(tinted.cgImage(forProposedRect: nil, context: nil, hints: nil))
        var opaque = 0
        for x in 0..<cg.width {
            for y in 0..<cg.height where try Self.rgba(cg, x: x, y: y).3 > 0.5 {
                opaque += 1
            }
        }
        #expect(opaque > 0)
        #expect(opaque < cg.width * cg.height, "a mark should not be a solid block")
    }
}
