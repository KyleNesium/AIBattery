import SwiftUI

struct TokenHealthSection: View {
    let sessions: [TokenHealthStatus]
    var onRefresh: (() -> Void)? = nil
    @State private var selectedIndex: Int = 0

    /// Convenience init for single session (backward compat)
    init(health: TokenHealthStatus, onRefresh: (() -> Void)? = nil) {
        self.sessions = [health]
        self.onRefresh = onRefresh
    }

    init(sessions: [TokenHealthStatus], onRefresh: (() -> Void)? = nil) {
        self.sessions = sessions
        self.onRefresh = onRefresh
    }

    private var health: TokenHealthStatus {
        guard !sessions.isEmpty else {
            // Shouldn't happen — callers guard for empty sessions — but avoid a crash.
            return TokenHealthStatus.empty
        }
        let idx = min(selectedIndex, sessions.count - 1)
        return sessions[max(idx, 0)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with session toggle
            HStack {
                Text("Context Health")
                    .font(.subheadline.bold())
                    .help("Percentage of usable context window consumed")
                Spacer()

                if sessions.count > 1 {
                    sessionToggle
                }

                if let onRefresh {
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Refresh for latest session")
                }
                healthBadge
            }

            // Session info on its own line for full width
            sessionInfoLabel

            // Gauge bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.1))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(bandColor)
                        .frame(width: geometry.size.width * min(CGFloat(health.usagePercentage) / 100.0, 1.0), height: 8)
                        .animation(.easeInOut(duration: 0.4), value: health.usagePercentage)
                }
            }
            .frame(height: 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Context usage \(Int(health.usagePercentage)) percent")
            .accessibilityValue("\(TokenFormatter.format(health.remainingTokens)) tokens remaining")

            // Detail row
            HStack {
                Text("~\(TokenFormatter.format(health.remainingTokens)) of \(TokenFormatter.format(health.usableWindow)) usable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .copyable("~\(TokenFormatter.format(health.remainingTokens)) of \(TokenFormatter.format(health.usableWindow)) usable")
                Spacer()
                Text("\(health.turnCount) turns · \(health.model.isEmpty ? "unknown" : ModelNameMapper.displayName(for: health.model))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .help("Conversation turns in this session")
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("~\(TokenFormatter.format(health.remainingTokens)) of \(TokenFormatter.format(health.usableWindow)) usable, \(health.turnCount) turns, \(health.model.isEmpty ? "unknown model" : ModelNameMapper.displayName(for: health.model))")

            // Recommended minimum context hint
            if health.band == .orange || health.band == .red {
                let safeMin = health.usableWindow / 5 // 20% of usable window
                Text("(keep above ~\(TokenFormatter.format(safeMin)) for best quality)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .help("Recommended minimum tokens to maintain response quality")
            }

            // Warnings
            ForEach(health.warnings) { warning in
                HStack(spacing: 4) {
                    Image(systemName: warning.severity == .strong ? "exclamationmark.triangle.fill" : "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(warning.severity == .strong ? ThemeColors.danger : ThemeColors.caution)
                    Text(warning.message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Suggested action
            if let action = health.suggestedAction {
                Text(action)
                    .font(.caption2)
                    .foregroundStyle(health.band == .red ? ThemeColors.danger : ThemeColors.caution)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .gesture(
            sessions.count > 1 ?
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    let horizontal = value.translation.width
                    guard abs(horizontal) > abs(value.translation.height) else { return }
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if horizontal < 0 {
                            selectedIndex = min(selectedIndex + 1, sessions.count - 1)
                        } else {
                            selectedIndex = max(selectedIndex - 1, 0)
                        }
                    }
                }
            : nil
        )
    }

    /// Chevron buttons to cycle through sessions
    private var sessionToggle: some View {
        HStack(spacing: 2) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectedIndex = max(selectedIndex - 1, 0)
                }
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 8, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(selectedIndex > 0 ? .secondary : .quaternary)
            .disabled(selectedIndex == 0)
            .accessibilityLabel("Previous session")

            Text("\(selectedIndex + 1)/\(sessions.count)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)

            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectedIndex = min(selectedIndex + 1, sessions.count - 1)
                }
            }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(selectedIndex < sessions.count - 1 ? .secondary : .quaternary)
            .disabled(selectedIndex >= sessions.count - 1)
            .accessibilityLabel("Next session")
        }
        .help("Browse recent sessions")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Session \(selectedIndex + 1) of \(sessions.count)")
    }

    private var sessionInfoLabel: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Line 1: project · branch · session ID prefix + stale badge
            HStack(spacing: 4) {
                let topParts = sessionTopParts
                Text(topParts.isEmpty ? "Latest session" : topParts.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let idleMinutes = staleIdleMinutes {
                    HStack(spacing: 2) {
                        Circle()
                            .fill(ThemeColors.caution)
                            .frame(width: 5, height: 5)
                        Text("Idle \(idleMinutes)m")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(ThemeColors.caution)
                    }
                    .help("Session has been idle — context may be stale")
                }
            }

            // Line 2: duration · last active · velocity
            let bottomParts = sessionBottomParts
            if !bottomParts.isEmpty {
                Text(bottomParts.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .help(sessionDetailTooltip)
    }

    /// Minutes idle if session is stale (>30 min with non-green band), otherwise nil.
    private var staleIdleMinutes: Int? {
        guard let lastActivity = health.lastActivity, health.band != .green else { return nil }
        let idle = Date().timeIntervalSince(lastActivity)
        guard idle > 30 * 60 else { return nil }
        return Int(idle / 60)
    }

    /// Full session detail string for tooltip hover.
    private var sessionDetailTooltip: String {
        var parts: [String] = []
        if !health.id.isEmpty { parts.append("Session: \(health.id)") }
        if !health.model.isEmpty { parts.append("Model: \(ModelNameMapper.displayName(for: health.model))") }
        parts.append("Context: \(TokenFormatter.format(health.totalUsed))/\(TokenFormatter.format(health.usableWindow))")
        parts.append("Input: \(TokenFormatter.format(health.inputTokens)) · Output: \(TokenFormatter.format(health.outputTokens))")
        if health.cacheReadTokens > 0 || health.cacheWriteTokens > 0 {
            parts.append("Cache R: \(TokenFormatter.format(health.cacheReadTokens)) · W: \(TokenFormatter.format(health.cacheWriteTokens))")
        }
        parts.append("Turns: \(health.turnCount)")
        if let start = health.sessionStart {
            parts.append("Started: \(Self.formatSessionTime(start))")
        }
        if !health.warnings.isEmpty {
            parts.append("Warnings: \(health.warnings.map(\.message).joined(separator: ", "))")
        }
        return parts.joined(separator: "\n")
    }

    private var sessionTopParts: [String] {
        var parts: [String] = []
        if let name = health.projectName {
            parts.append(name)
        }
        if let branch = health.gitBranch, branch != "HEAD", !branch.isEmpty {
            parts.append(branch)
        }
        // Short session ID prefix for cross-referencing with Claude Code
        if !health.id.isEmpty {
            let prefix = String(health.id.prefix(8))
            parts.append(prefix)
        }
        return parts
    }

    private var sessionBottomParts: [String] {
        var parts: [String] = []
        if let duration = health.sessionDuration {
            let hours = Int(duration) / 3600
            let mins = (Int(duration) % 3600) / 60
            if hours > 0 {
                parts.append("\(hours)h \(mins)m")
            } else {
                parts.append("\(mins)m")
            }
        }
        if let lastActivity = health.lastActivity {
            parts.append(Self.formatSessionTime(lastActivity))
        } else if let start = health.sessionStart {
            parts.append(Self.formatSessionTime(start))
        }
        if let velocity = health.tokensPerMinute, velocity > 0 {
            parts.append("\(TokenFormatter.format(Int(velocity)))/min")
        }
        return parts
    }

    // MARK: - Static Formatters

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"
        return f
    }()

    /// Format a session timestamp: "Today 14:32", "Yesterday 09:15", or "Feb 10, 14:32"
    private static func formatSessionTime(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = timeFormatter.string(from: date)

        if calendar.isDateInToday(date) {
            return "Today \(time)"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday \(time)"
        } else {
            return "\(dayFormatter.string(from: date)), \(time)"
        }
    }

    private var healthBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(bandColor)
                .frame(width: 8, height: 8)
            Text("\(Int(health.usagePercentage))%")
                .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.4), value: Int(health.usagePercentage))
                .copyable("\(Int(health.usagePercentage))%")
        }
    }

    private var bandColor: Color {
        ThemeColors.bandColor(health.band)
    }
}
