#if APP_SANDBOX
import Foundation
import AppKit

/// Manages security-scoped bookmark persistence for `~/.claude/` access under App Sandbox.
/// Only active when `APP_SANDBOX` compile flag is set (dormant in direct-download builds).
@MainActor
public final class SandboxAccessManager {
    static let shared = SandboxAccessManager()

    private let bookmarkKey = "aibattery_claudeDirBookmark"

    /// Whether we have a valid bookmark for ~/.claude/.
    var hasAccess: Bool { resolveBookmark() != nil }

    /// Prompt user to select ~/.claude/ directory via NSOpenPanel.
    /// Returns the security-scoped URL on success.
    func requestAccess() -> URL? {
        let panel = NSOpenPanel()
        panel.message = "AI Battery needs access to your ~/.claude folder to read usage data."
        panel.prompt = "Grant Access"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        // Store security-scoped bookmark
        if let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        }
        return url
    }

    /// Resolve stored bookmark to a security-scoped URL.
    func resolveBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        if isStale {
            // Re-store refreshed bookmark
            if let fresh = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                UserDefaults.standard.set(fresh, forKey: bookmarkKey)
            }
        }
        return url
    }

    /// Start accessing the security-scoped resource. Call on app launch.
    func startAccessing() -> Bool {
        guard let url = resolveBookmark() else { return false }
        return url.startAccessingSecurityScopedResource()
    }
}
#endif
