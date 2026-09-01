import Foundation

// MARK: - Session detail computation (extracted from TokenHealthSection)

/// Pure helpers for formatting session metadata — no view code.
enum SessionInfoFormatter {
    /// Project name and branch for display.
    static func labelParts(for health: TokenHealthStatus) -> [String] {
        var parts: [String] = []
        if let name = health.projectName {
            parts.append(name)
        }
        if let branch = health.gitBranch, branch != "HEAD", !branch.isEmpty {
            parts.append(branch)
        }
        return parts
    }

    /// 8-char session ID prefix for cross-referencing with Claude Code.
    static func idPrefix(for health: TokenHealthStatus) -> String? {
        guard !health.id.isEmpty else { return nil }
        return String(health.id.prefix(8))
    }

    /// Bottom line parts: duration, last activity, velocity.
    static func bottomParts(for health: TokenHealthStatus) -> [String] {
        var parts: [String] = []
        if let duration = health.sessionDuration {
            parts.append(DurationFormatter.compact(duration))
        }
        if let lastActivity = health.lastActivity {
            parts.append(formatSessionTime(lastActivity))
        } else if let start = health.sessionStart {
            parts.append(formatSessionTime(start))
        }
        if let velocity = health.tokensPerMinute, velocity > 0 {
            parts.append("\(TokenFormatter.format(Int(velocity)))/min")
        }
        return parts
    }

    /// Minutes idle if session is stale (>30 min with non-green band), otherwise nil.
    static func staleIdleMinutes(for health: TokenHealthStatus) -> Int? {
        guard let lastActivity = health.lastActivity, health.band != .green else { return nil }
        let idle = Date().timeIntervalSince(lastActivity)
        guard idle > 30 * 60 else { return nil }
        return Int(idle / 60)
    }

    /// Full session detail string for tooltip hover.
    static func detailTooltip(for health: TokenHealthStatus) -> String {
        var parts: [String] = []
        if !health.id.isEmpty {
            parts.append("Session: \(health.id)")
        }
        if !health.model.isEmpty {
            parts.append("Model: \(ModelNameMapper.displayName(for: health.model))")
        }
        parts.append("Context: \(TokenFormatter.format(health.totalUsed))/\(TokenFormatter.format(health.usableWindow))")
        parts.append("Input: \(TokenFormatter.format(health.inputTokens)) · Output: \(TokenFormatter.format(health.outputTokens))")
        if health.cacheReadTokens > 0 || health.cacheWriteTokens > 0 {
            parts.append("Cache R: \(TokenFormatter.format(health.cacheReadTokens)) · W: \(TokenFormatter.format(health.cacheWriteTokens))")
        }
        parts.append("Turns: \(health.turnCount)")
        if let start = health.sessionStart {
            parts.append("Started: \(formatSessionTime(start))")
        }
        if !health.warnings.isEmpty {
            parts.append("Warnings: \(health.warnings.map(\.message).joined(separator: ", "))")
        }
        return parts.joined(separator: "\n")
    }

    /// Markdown-formatted session details for clipboard export.
    /// Includes exact token counts (not abbreviated) and all visible metadata.
    static func copyableDetails(for health: TokenHealthStatus) -> String {
        var lines: [String] = []
        lines.append("Context Health")
        lines.append("─────────────")
        if !health.id.isEmpty {
            lines.append("Session:  \(health.id)")
        }
        if !health.model.isEmpty {
            lines.append("Model:    \(ModelNameMapper.displayName(for: health.model))")
        }
        if let name = health.projectName {
            lines.append("Project:  \(name)")
        }
        if let branch = health.gitBranch, branch != "HEAD", !branch.isEmpty {
            lines.append("Branch:   \(branch)")
        }
        lines.append("Context:  \(health.totalUsed)/\(health.usableWindow) (\(Int(health.usagePercentage))%)")
        lines.append("Input:    \(health.inputTokens)")
        lines.append("Output:   \(health.outputTokens)")
        if health.cacheReadTokens > 0 {
            lines.append("Cache R:  \(health.cacheReadTokens)")
        }
        if health.cacheWriteTokens > 0 {
            lines.append("Cache W:  \(health.cacheWriteTokens)")
        }
        lines.append("Turns:    \(health.turnCount)")
        if let duration = health.sessionDuration {
            lines.append("Duration: \(DurationFormatter.compact(duration))")
        }
        if let velocity = health.tokensPerMinute, velocity > 0 {
            lines.append("Velocity: \(Int(velocity)) tok/min")
        }
        if let start = health.sessionStart {
            lines.append("Started:  \(formatSessionTime(start))")
        }
        if let lastActivity = health.lastActivity {
            lines.append("Last:     \(formatSessionTime(lastActivity))")
        }
        if !health.warnings.isEmpty {
            for w in health.warnings {
                lines.append("⚠ \(w.message)")
            }
        }
        if let action = health.suggestedAction {
            lines.append("→ \(action)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Time formatting

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f
    }()

    /// Format a session timestamp: "Today 14:32", "Yesterday 09:15", or "Feb 10, 14:32"
    private static let calendar = Calendar.current

    static func formatSessionTime(_ date: Date, now: Date = Date()) -> String {
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 60 {
            return "just now"
        }
        if elapsed < 3_600 {
            return "\(Int(elapsed / 60))m ago"
        }
        let time = timeFormatter.string(from: date)

        if calendar.isDate(date, inSameDayAs: now) {
            return "Today \(time)"
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
                  calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday \(time)"
        } else {
            return "\(dayFormatter.string(from: date)), \(time)"
        }
    }
}
