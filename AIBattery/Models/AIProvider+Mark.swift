import AppKit
import Foundation

/// Brand marks for the header badge — the real Claude and OpenAI logos
/// (Simple Icons, CC0; `AIBattery/Resources/*.svg`), rendered as template
/// images so they take whatever tint the badge gives them.
///
/// Resource lookup is explicit and never traps. SwiftPM's generated
/// `Bundle.module` only searches `Bundle.main.bundleURL/<bundle>` and an
/// absolute path on the build machine, then calls `fatalError` — a shipped
/// `.app` keeps the bundle in `Contents/Resources`, so relying on it would
/// crash every install on the first badge while passing on the dev machine.
public extension AIProvider {
    /// Bundled SVG basename (`Resources/<name>.svg`).
    var markResourceName: String {
        switch self {
        case .claude: "claude"
        case .codex: "openai"
        }
    }

    /// SwiftPM resource bundle name: `<package>_<target>.bundle`.
    static let resourceBundleName = "AIBattery_AIBatteryCore.bundle"

    /// Where the resource bundle can live, in priority order:
    /// 1. `Contents/Resources` of the packaged app (what `scripts/build-app.sh` ships)
    /// 2. the executable's directory (`swift run` / bare `.build/release/AIBattery`)
    /// 3. next to the loaded module (`swift test`: the test bundle's parent is `.build/<config>/`)
    nonisolated static var defaultMarkSearchRoots: [URL] {
        var roots: [URL] = []
        if let resources = Bundle.main.resourceURL {
            roots.append(resources)
        }
        roots.append(Bundle.main.bundleURL)
        roots.append(Bundle(for: MarkCache.self).bundleURL.deletingLastPathComponent())
        return roots
    }

    /// First `<root>/<resourceBundleName>/Resources/<name>.svg` that exists, else nil.
    nonisolated static func markURL(for provider: AIProvider, searchRoots: [URL] = defaultMarkSearchRoots) -> URL? {
        for root in searchRoots {
            let candidate = root
                .appendingPathComponent(resourceBundleName)
                .appendingPathComponent("Resources")
                .appendingPathComponent("\(provider.markResourceName).svg")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
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
