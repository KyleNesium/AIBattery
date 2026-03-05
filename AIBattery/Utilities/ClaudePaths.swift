import Foundation

/// Centralized file paths for Claude Code data.
/// All paths are relative to the user's home directory.
enum ClaudePaths {
    #if APP_SANDBOX
    /// Under App Sandbox, `FileManager.homeDirectoryForCurrentUser` returns the container path.
    /// Use POSIX `getpwuid` to resolve the real home directory where `~/.claude/` lives.
    private static let home: URL = {
        let pw = getpwuid(getuid())!
        return URL(fileURLWithPath: String(cString: pw.pointee.pw_dir))
    }()
    #else
    private static let home = FileManager.default.homeDirectoryForCurrentUser
    #endif

    /// `~/.claude/stats-cache.json` — historical usage aggregates
    static let statsCache: URL = home.appendingPathComponent(".claude/stats-cache.json")

    /// `~/.claude/stats-cache.json` as a POSIX path (for `open()` / `FileManager`)
    static let statsCachePath: String = statsCache.path

    /// `~/.claude/projects/` — session JSONL directory
    static let projects: URL = home.appendingPathComponent(".claude/projects")

    /// `~/.claude/projects/` as a POSIX path
    static let projectsPath: String = projects.path
}
