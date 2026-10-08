import AppKit
import Foundation

/// Brand marks for the header badge — the real Claude and OpenAI logos
/// (Simple Icons, CC0; `AIBattery/Resources/*.svg`), rendered as template
/// images so they take whatever tint the badge gives them.
public extension AIProvider {
    /// Bundled SVG basename (`Resources/<name>.svg`).
    var markResourceName: String {
        switch self {
        case .claude: "claude"
        case .codex: "openai"
        }
    }

    nonisolated static func markURL(for provider: AIProvider) -> URL? {
        Bundle.module.url(forResource: provider.markResourceName, withExtension: "svg", subdirectory: "Resources")
    }

    /// Template `NSImage` of the mark, loaded once per provider. Nil only if the
    /// resource is missing or unreadable — the badge then falls back to `symbolName`.
    var markImage: NSImage? {
        Self.markCache.image(for: self)
    }

    private static let markCache = MarkCache()
}

extension NSImage {
    /// A flat copy of a template image filled with `color` at `size` — for places
    /// that can't tint templates themselves (NSTextAttachment inside a drawn NSImage).
    func tinted(_ color: NSColor, size: NSSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            self.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}

/// One-time SVG decode per provider; `NSImage` is immutable once `isTemplate` is set.
private final class MarkCache: @unchecked Sendable {
    private let lock = NSLock()
    private var images: [AIProvider: NSImage] = [:]

    func image(for provider: AIProvider) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = images[provider] {
            return cached
        }
        guard let url = AIProvider.markURL(for: provider), let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = true
        images[provider] = image
        return image
    }
}
