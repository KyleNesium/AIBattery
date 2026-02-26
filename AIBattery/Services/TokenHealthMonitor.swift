import Foundation

/// Analyzes session token usage and produces health assessments.
final class TokenHealthMonitor {
    static let shared = TokenHealthMonitor()

    private let config: TokenHealthConfig

    init(config: TokenHealthConfig = .default) {
        self.config = config
    }

    /// Single-pass assessment: groups entries once, returns current session health + top N recent sessions.
    func assessSessions(entries: [AssistantUsageEntry], topLimit: Int = 5) -> (current: TokenHealthStatus?, top: [TokenHealthStatus]) {
        guard let latestEntry = entries.last else { return (nil, []) }

        let now = Date()
        let cutoff = now.addingTimeInterval(-24 * 60 * 60)
        let currentSessionId = latestEntry.sessionId
        let grouped = Dictionary(grouping: entries, by: \.sessionId)
        var current: TokenHealthStatus?
        var recentResults: [TokenHealthStatus] = []

        for (sessionId, sessionEntries) in grouped {
            guard !sessionEntries.isEmpty, !sessionId.isEmpty else { continue }
            let isCurrent = sessionId == currentSessionId

            // Skip expensive assessment for sessions with no activity in the last 24h
            // (unless it's the current session — always assess that one).
            if !isCurrent, let last = sessionEntries.last?.timestamp, last <= cutoff {
                continue
            }

            let model = sessionEntries.last?.model ?? ""
            guard let status = assess(sessionEntries: sessionEntries, sessionId: sessionId, model: model, now: now) else { continue }

            if isCurrent { current = status }
            if (status.lastActivity ?? .distantPast) > cutoff {
                recentResults.append(status)
            }
        }

        recentResults.sort { ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast) }
        let top = Array(recentResults.prefix(topLimit))

        return (current, top)
    }

    /// Convenience: assess health for the most recent session only.
    func assessCurrentSession(entries: [AssistantUsageEntry]) -> TokenHealthStatus? {
        assessSessions(entries: entries).current
    }

    /// Convenience: return top N sessions sorted by most recent activity.
    func topSessions(entries: [AssistantUsageEntry], limit: Int = 5) -> [TokenHealthStatus] {
        assessSessions(entries: entries, topLimit: limit).top
    }

    // MARK: - Core Assessment

    private func assess(sessionEntries: [AssistantUsageEntry], sessionId: String = "", model: String, now: Date = Date()) -> TokenHealthStatus? {
        guard let latestEntry = sessionEntries.last else { return nil }
        let contextWindow = TokenHealthConfig.contextWindow(for: model)
        let usableWindow = Int(Double(contextWindow) * TokenHealthConfig.usableContextRatio)
        let turnCount = sessionEntries.count

        // Latest entry's input tokens are cumulative (full context).
        // Cache tokens are also part of the context window footprint.
        // Output tokens are per-message, so sum across all entries.
        let inputTokens = latestEntry.inputTokens
        let cacheReadTokens = latestEntry.cacheReadTokens
        let cacheWriteTokens = latestEntry.cacheWriteTokens
        let outputTokens = sessionEntries.reduce(0) { $0 + $1.outputTokens }

        // Total context used includes input + cache + all outputs.
        // Guard against overflow from corrupted data — cap each component at contextWindow.
        let safeInput = min(inputTokens, contextWindow)
        let safeCacheRead = min(cacheReadTokens, contextWindow)
        let safeCacheWrite = min(cacheWriteTokens, contextWindow)
        let safeOutput = min(outputTokens, contextWindow)
        let totalUsed = min(safeInput + safeCacheRead + safeCacheWrite + safeOutput, contextWindow)

        // Percentage is against the usable window (80% of raw), not the full window.
        // 100% here = Claude Code is about to auto-compact.
        let usagePercentage = Double(totalUsed) / Double(usableWindow) * 100.0
        let remaining = max(usableWindow - totalUsed, 0)

        // Determine band
        let band: HealthBand
        if usagePercentage >= config.redThreshold {
            band = .red
        } else if usagePercentage >= config.greenThreshold {
            band = .orange
        } else {
            band = .green
        }

        // Collect warnings
        var warnings: [HealthWarning] = []

        // 1. High turn count
        if turnCount > config.turnCountStrong {
            warnings.append(HealthWarning(
                severity: .strong,
                message: "Long conversation (\(turnCount) turns)",
                suggestion: "Quality may be degrading. Consider starting fresh."
            ))
        } else if turnCount > config.turnCountMild {
            warnings.append(HealthWarning(
                severity: .mild,
                message: "Extended conversation (\(turnCount) turns)",
                suggestion: "Consider starting a fresh conversation."
            ))
        }

        // 2. Input-to-output ratio imbalance (include cache in "input" side)
        let totalInput = inputTokens + cacheReadTokens + cacheWriteTokens
        if outputTokens > 0 {
            let ratio = Double(totalInput) / Double(outputTokens)
            if ratio > config.inputOutputRatioThreshold {
                warnings.append(HealthWarning(
                    severity: .mild,
                    message: "High input-to-output ratio (\(Int(ratio)):1)",
                    suggestion: "You may be over-providing context."
                ))
            }
        }

        // 3. Zero-output sessions (likely stuck or erroring)
        if outputTokens == 0 && turnCount > config.zeroOutputTurnThreshold {
            warnings.append(HealthWarning(
                severity: .strong,
                message: "No output after \(turnCount) turns",
                suggestion: "Session may be stuck. Check for errors."
            ))
        }

        // 4. Rapid token consumption (short session, high usage)
        if let firstTs = sessionEntries.first?.timestamp,
           let lastTs = sessionEntries.last?.timestamp,
           lastTs.timeIntervalSince(firstTs) < Double(config.rapidConsumptionSeconds) && totalUsed > config.rapidConsumptionTokens {
            warnings.append(HealthWarning(
                severity: .mild,
                message: "Rapid token consumption detected",
                suggestion: "High token usage in under a minute."
            ))
        }

        // 5. Stale session (idle too long with non-green health)
        if let lastActivity = sessionEntries.last?.timestamp,
           now.timeIntervalSince(lastActivity) > Double(config.staleSessionMinutes * 60),
           band != .green {
            let idleMinutes = Int(now.timeIntervalSince(lastActivity) / 60)
            warnings.append(HealthWarning(
                severity: .mild,
                message: "Session idle for \(idleMinutes) min",
                suggestion: "Context may be stale. Consider starting fresh."
            ))
        }

        // 6. Token velocity (tokens per minute)
        // Use totalUsed (not sum of all entries, which double-counts cumulative input)
        var tokensPerMinute: Double? = nil
        if sessionEntries.count >= 2,
           let first = sessionEntries.first,
           let last = sessionEntries.last {
            let duration = last.timestamp.timeIntervalSince(first.timestamp)
            if duration > config.velocityMinDuration {
                tokensPerMinute = Double(totalUsed) / (duration / 60.0)
            }
        }

        // Project name from the first entry with cwd (session identity/origin).
        // Git branch from the latest entry (current working state).
        let firstCwdEntry = sessionEntries.first(where: { $0.cwd != nil })
        let latestCwdEntry = sessionEntries.last(where: { $0.cwd != nil })
        let projectName: String? = firstCwdEntry?.cwd.flatMap { URL(fileURLWithPath: $0).lastPathComponent }
        let gitBranch: String? = latestCwdEntry?.gitBranch

        // Session timing
        let sessionStart = sessionEntries.first?.timestamp
        let sessionDuration: TimeInterval? = {
            guard let first = sessionEntries.first?.timestamp,
                  let last = sessionEntries.last?.timestamp else { return nil }
            let d = last.timeIntervalSince(first)
            return d > 0 ? d : nil
        }()

        return TokenHealthStatus(
            id: sessionId,
            band: band,
            usagePercentage: min(usagePercentage, 100),
            totalUsed: totalUsed,
            contextWindow: contextWindow,
            usableWindow: usableWindow,
            remainingTokens: remaining,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheWriteTokens: cacheWriteTokens,
            model: model,
            turnCount: turnCount,
            warnings: warnings,
            tokensPerMinute: tokensPerMinute,
            projectName: projectName,
            gitBranch: gitBranch,
            sessionStart: sessionStart,
            sessionDuration: sessionDuration,
            lastActivity: sessionEntries.last?.timestamp
        )
    }
}
