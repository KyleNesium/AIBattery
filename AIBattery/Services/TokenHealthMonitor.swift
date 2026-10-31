import Foundation

/// Analyzes session token usage and produces health assessments.
final class TokenHealthMonitor: Sendable {
    static let shared = TokenHealthMonitor()

    private let config: TokenHealthConfig

    init(config: TokenHealthConfig = .default) {
        self.config = config
    }

    /// Single-pass assessment: groups entries once, returns current session health + top N recent sessions.
    /// - Parameter idleCutoffMinutes: Hide sessions idle longer than this. 0 = never hide (uses 24h performance bound).
    func assessSessions(entries: [AssistantUsageEntry], topLimit: Int = 5, idleCutoffMinutes: Int = 0) -> (current: TokenHealthStatus?, top: [TokenHealthStatus]) {
        guard let latestEntry = entries.last else { return (nil, []) }

        let now = Date()
        let cutoffSeconds: TimeInterval = idleCutoffMinutes > 0
            ? TimeInterval(idleCutoffMinutes * 60)
            : 24 * 60 * 60
        let cutoff = now.addingTimeInterval(-cutoffSeconds)
        let currentSessionId = latestEntry.sessionId

        // Binary search for cutoff index — entries are sorted by timestamp.
        // Only scan from cutoff forward instead of filtering all entries (O(log N + recent) vs O(N)).
        let cutoffIndex = binarySearchCutoff(entries: entries, cutoff: cutoff)

        // The current session's older turns are found by scanning BACKWARDS, so they come
        // out newest-first. They are collected separately and flipped, because
        // `Dictionary(grouping:)` preserves insertion order and `assess` reads `.last` as
        // the latest turn and `.first` as the session start. Appending them directly made
        // the "latest" entry the session's very first turn: the context bar read that
        // turn's cumulative input (far too low), the duration came out negative, and the
        // negative interval always satisfied the rapid-consumption check.
        var olderCurrentSessionEntries: [AssistantUsageEntry] = []

        for i in stride(from: cutoffIndex - 1, through: 0, by: -1) {
            if entries[i].sessionId == currentSessionId {
                olderCurrentSessionEntries.append(entries[i])
            } else {
                // Stop scanning once we hit a different session far enough back
                // (current session entries tend to be clustered near the end)
                if entries[i].timestamp < cutoff.addingTimeInterval(-3_600) {
                    break
                }
            }
        }

        var relevantEntries: [AssistantUsageEntry] = []
        relevantEntries.reserveCapacity(entries.count - cutoffIndex + olderCurrentSessionEntries.count)
        // Everything before the cutoff is older than everything after it, so flipping the
        // backward scan and putting it first yields one ascending run.
        relevantEntries.append(contentsOf: olderCurrentSessionEntries.reversed())
        for i in cutoffIndex..<entries.count {
            relevantEntries.append(entries[i])
        }

        let grouped = Dictionary(grouping: relevantEntries, by: \.sessionId)
        var current: TokenHealthStatus?
        var recentResults: [TokenHealthStatus] = []

        for (sessionId, sessionEntries) in grouped {
            guard !sessionEntries.isEmpty, !sessionId.isEmpty else { continue }

            let model = Self.lastRealEntry(in: sessionEntries)?.model ?? ""
            guard let status = assess(sessionEntries: sessionEntries, sessionId: sessionId, model: model, now: now) else { continue }

            if sessionId == currentSessionId {
                current = status
            }
            if (status.lastActivity ?? .distantPast) > cutoff {
                recentResults.append(status)
            }
        }

        // Always include the current session so it appears in the session browser
        // even when idle past the cutoff (it's still the most relevant session).
        if let current, !recentResults.contains(where: { $0.id == current.id }) {
            recentResults.append(current)
        }

        // Highest context usage first so the most-consumed session is always position 1
        recentResults.sort { $0.usagePercentage > $1.usagePercentage }
        let top = Array(recentResults.prefix(topLimit))

        return (current, top)
    }

    /// Binary search for the first entry index with timestamp > cutoff.
    /// Entries must be sorted by timestamp ascending. An entry exactly AT the
    /// cutoff is excluded (strict `>`). Internal (not private) so boundary
    /// tests can pin that semantic directly.
    func binarySearchCutoff(entries: [AssistantUsageEntry], cutoff: Date) -> Int {
        var lo = 0, hi = entries.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if entries[mid].timestamp > cutoff {
                hi = mid
            } else {
                lo = mid + 1
            }
        }
        return lo
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

    /// The last entry that actually carries a turn's usage.
    ///
    /// Claude Code writes `<synthetic>` pseudo-messages for interrupts and errors, and
    /// they carry all-zero usage. Reading the context estimate off the literal last
    /// entry meant a session at 700K/1M reported "0%, 1,000,000 remaining" — green, and
    /// unable to escalate — the moment the user pressed Esc. Falls back to the last
    /// entry when a session has nothing else, so a synthetic-only session still assesses.
    static func lastRealEntry(in entries: [AssistantUsageEntry]) -> AssistantUsageEntry? {
        entries.last(where: { isRealModel($0.model) }) ?? entries.last
    }

    /// A provider model id, as opposed to `<synthetic>` and friends. Provider-agnostic
    /// on purpose: one monitor assesses both providers' sessions.
    static func isRealModel(_ modelId: String) -> Bool {
        modelId.hasPrefix("claude-") || modelId.hasPrefix("gpt-")
    }

    private func assess(sessionEntries: [AssistantUsageEntry], sessionId: String = "", model: String, now: Date = Date()) -> TokenHealthStatus? {
        guard let latestEntry = Self.lastRealEntry(in: sessionEntries) else { return nil }
        // The provider's own figure wins (Codex writes `model_context_window` on every
        // token_count); the table is the fallback (Claude logs carry no window).
        let contextWindow = latestEntry.contextWindow ?? TokenHealthConfig.contextWindow(for: model)
        let turnCount = sessionEntries.count

        // Bind timestamps once — avoids repeated optional chain traversals
        let firstTimestamp = sessionEntries.first?.timestamp
        let lastTimestamp = latestEntry.timestamp

        // Latest entry's input tokens are cumulative (full conversation context).
        // Cache tokens are separate non-overlapping components of the same input.
        // Together, input + cacheRead + cacheWrite = total prompt tokens for the latest turn.
        // Only the latest output matters for context estimation (previous outputs are
        // already folded into the latest input_tokens by the API).
        let inputTokens = latestEntry.inputTokens
        let cacheReadTokens = latestEntry.cacheReadTokens
        let cacheWriteTokens = latestEntry.cacheWriteTokens
        let outputTokens = latestEntry.outputTokens
        let totalOutputTokens = sessionEntries.reduce(0) { $0 + $1.outputTokens }
        let totalReasoningTokens = sessionEntries.reduce(0) { $0 + $1.reasoningTokens }

        // The window is NOT widened to fit what has been observed. That tier bump dates
        // from the 200K era, when exceeding the table really did mean the table was
        // stale; the default is 1M now, so the likelier reading of "over the window" is
        // that the session is over the window. Bumping halved the percentage exactly
        // when context was most critical — 199K/200K (red) became 201K/500K (green) and
        // the warning vanished as the session got worse. Overflow clamps at 100%, red,
        // via the `min(..., contextWindow)` caps below.

        let usableWindow = Int(Double(contextWindow) * TokenHealthConfig.usableContextRatio)

        // Total context used: latest full input + latest output (next turn will include it).
        // Guard against overflow from corrupted data — cap each component at contextWindow.
        let safeInput = min(inputTokens, contextWindow)
        let safeCacheRead = min(cacheReadTokens, contextWindow)
        let safeCacheWrite = min(cacheWriteTokens, contextWindow)
        let safeOutput = min(outputTokens, contextWindow)
        let totalUsed = min(safeInput + safeCacheRead + safeCacheWrite + safeOutput, contextWindow)

        // Percentage is against the usable window (80% of raw), not the full window.
        // 100% here = Claude Code is about to auto-compact.
        let usagePercentage = usableWindow > 0 ? Double(totalUsed) / Double(usableWindow) * 100.0 : 0
        let remaining = max(usableWindow - totalUsed, 0)

        // Determine band
        let band: HealthBand = if usagePercentage >= config.redThreshold {
            .red
        } else if usagePercentage >= config.greenThreshold {
            .orange
        } else {
            .green
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
                severity: .info,
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
                    severity: .info,
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
        if let firstTs = firstTimestamp,
           lastTimestamp.timeIntervalSince(firstTs) < Double(config.rapidConsumptionSeconds) && totalUsed > config.rapidConsumptionTokens {
            warnings.append(HealthWarning(
                severity: .mild,
                message: "Rapid token consumption detected",
                suggestion: "High token usage in under a minute."
            ))
        }

        // 5. Stale session (idle too long with non-green health)
        if now.timeIntervalSince(lastTimestamp) > Double(config.staleSessionMinutes * 60),
           band != .green {
            let idleMinutes = Int(now.timeIntervalSince(lastTimestamp) / 60)
            warnings.append(HealthWarning(
                severity: .mild,
                message: "Session idle for \(idleMinutes) min",
                suggestion: "Context may be stale. Consider starting fresh."
            ))
        }

        // 6. Token velocity (tokens per minute)
        // Use totalUsed (not sum of all entries, which double-counts cumulative input)
        var tokensPerMinute: Double?
        if let firstTs = firstTimestamp, turnCount >= 2 {
            let duration = lastTimestamp.timeIntervalSince(firstTs)
            if duration > config.velocityMinDuration {
                tokensPerMinute = Double(totalUsed) / (duration / 60.0)
            }
        }

        // Project name from the first entry with cwd (session identity/origin).
        // Git branch from the latest entry (current working state).
        let firstCwdEntry = sessionEntries.first(where: { $0.cwd != nil })
        let latestCwdEntry = sessionEntries.last(where: { $0.cwd != nil })
        let projectName: String? = firstCwdEntry?.cwd.flatMap { ($0 as NSString).lastPathComponent }
        let gitBranch: String? = latestCwdEntry?.gitBranch

        // Session timing
        let sessionDuration: TimeInterval? = {
            guard let firstTs = firstTimestamp else { return nil }
            let d = lastTimestamp.timeIntervalSince(firstTs)
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
            outputTokens: totalOutputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheWriteTokens: cacheWriteTokens,
            model: model,
            turnCount: turnCount,
            warnings: warnings,
            tokensPerMinute: tokensPerMinute,
            projectName: projectName,
            gitBranch: gitBranch,
            sessionStart: firstTimestamp,
            sessionDuration: sessionDuration,
            lastActivity: lastTimestamp,
            reasoningTokens: min(totalReasoningTokens, totalOutputTokens),
            effortLabel: latestEntry.effortLabel
        )
    }
}
