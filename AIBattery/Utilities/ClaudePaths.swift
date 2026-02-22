import Foundation

/// Centralized file paths for Claude Code data.
/// All paths are relative to the user's home directory.
enum ClaudePaths {
    private static let home = FileManager.default.homeDirectoryForCurrentUser

    /// `~/.claude/stats-cache.json` — historical usage aggregates
    static var statsCache: URL { home.appendingPathComponent(".claude/stats-cache.json") }

    /// `~/.claude/stats-cache.json` as a POSIX path (for `open()` / `FileManager`)
    static var statsCachePath: String { statsCache.path }

    /// `~/.claude/projects/` — session JSONL directory
    static var projects: URL { home.appendingPathComponent(".claude/projects") }

    /// `~/.claude/projects/` as a POSIX path
    static var projectsPath: String { projects.path }

    /// `~/.claude.json` — account info (billing type)
    static var accountConfig: URL { home.appendingPathComponent(".claude.json") }

    /// `~/.claude.json` as a POSIX path
    static var accountConfigPath: String { accountConfig.path }
}
