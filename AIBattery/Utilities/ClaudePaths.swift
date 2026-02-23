import Foundation

/// Centralized file paths for Claude Code data.
/// All paths are relative to the user's home directory.
enum ClaudePaths {
    private static let home = FileManager.default.homeDirectoryForCurrentUser

    /// `~/.claude/stats-cache.json` — historical usage aggregates
    static let statsCache: URL = home.appendingPathComponent(".claude/stats-cache.json")

    /// `~/.claude/stats-cache.json` as a POSIX path (for `open()` / `FileManager`)
    static let statsCachePath: String = statsCache.path

    /// `~/.claude/projects/` — session JSONL directory
    static let projects: URL = home.appendingPathComponent(".claude/projects")

    /// `~/.claude/projects/` as a POSIX path
    static let projectsPath: String = projects.path

    /// `~/.claude.json` — account info (billing type)
    static let accountConfig: URL = home.appendingPathComponent(".claude.json")

    /// `~/.claude.json` as a POSIX path
    static let accountConfigPath: String = accountConfig.path
}
