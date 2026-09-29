import Foundation

/// Centralized file paths for Codex CLI data. Read-only — AIBattery never writes here.
enum CodexPaths {
    private static let home = FileManager.default.homeDirectoryForCurrentUser
    /// `~/.codex/`
    static let root: URL = home.appendingPathComponent(".codex")
    /// `~/.codex/sessions/` — rollout JSONL, nested YYYY/MM/DD
    static let sessions: URL = root.appendingPathComponent("sessions")
    static let sessionsPath: String = sessions.path
    /// `~/.codex/auth.json` — the CLI's own login (import convenience)
    static let authJSON: URL = root.appendingPathComponent("auth.json")
    static let authJSONPath: String = authJSON.path
}
