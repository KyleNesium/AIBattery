import Foundation

/// Well-known filesystem locations for AIBattery's own data.
/// (Claude Code's directories live in `ClaudePaths` — this is ours.)
enum AppPaths {
    /// `~/Library/Application Support/AIBattery`, created if missing.
    /// The Application Support directory is guaranteed by macOS; its absence
    /// means a fundamentally broken environment, so failing fast is correct.
    /// Single home for the guard that was previously duplicated in
    /// `SingleInstanceGuard` and `TokenLedger`.
    static func applicationSupport() -> URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support directory unavailable")
        }
        let dir = appSupport.appendingPathComponent("AIBattery")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
