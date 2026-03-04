import Foundation

@MainActor
final class UsageAggregator {
    private let statsCacheReader: StatsCacheReader
    private let sessionLogReader: SessionLogReader

    init(statsCacheReader: StatsCacheReader, sessionLogReader: SessionLogReader) {
        self.statsCacheReader = statsCacheReader
        self.sessionLogReader = sessionLogReader
    }

    convenience init() {
        self.init(statsCacheReader: .shared, sessionLogReader: .shared)
    }

    private static let dateFormatter = DateFormatters.dateKey
    private static let isoFormatter = DateFormatters.iso8601

    // MARK: - Redundant aggregation skip

    private var cachedSnapshot: UsageSnapshot?
    private var lastEntryCount = 0
    private var lastStatsCacheModDate: Date?
    private var lastRateLimits: RateLimitUsage?
    private var lastIdleSessionMinutes: Int = -1

    func aggregate(rateLimits: RateLimitUsage?) -> UsageSnapshot {
        let statsCache = statsCacheReader.read()

        // Single JSONL scan — entries are already cached by SessionLogReader.
        let allEntries = sessionLogReader.readAllUsageEntries()

        // Idle session cutoff for context health (0 = never hide)
        let idleSessionMinutes = Int(UserDefaults.standard.double(forKey: UserDefaultsKeys.idleSessionMinutes))

        // Check fingerprint: skip re-aggregation if inputs haven't changed
        let statsCacheModDate = statsCacheReader.lastModificationDate
        if let cached = cachedSnapshot,
           allEntries.count == lastEntryCount,
           statsCacheModDate == lastStatsCacheModDate,
           rateLimits == lastRateLimits,
           idleSessionMinutes == lastIdleSessionMinutes {
            return cached
        }

        // Single-pass filter: extract today's entries.
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        var todayEntries: [AssistantUsageEntry] = []
        var todayModelIds = Set<String>()

        for entry in allEntries {
            if entry.timestamp >= today {
                todayEntries.append(entry)
                todayModelIds.insert(entry.model)
            }
        }

        let todayDate = Self.dateFormatter.string(from: now)
        let todayMessages = todayEntries.count
        let todaySessions = Set(todayEntries.map(\.sessionId)).count
        let todayToolCalls = statsCache?.dailyActivity
            .first(where: { $0.date == todayDate })?.toolCallCount ?? 0

        // Dates already covered by stats cache
        let cachedDates = Set(statsCache?.dailyModelTokens.map(\.date) ?? [])

        // Only show models active in the last 72 hours to reduce noise.
        // todayModelIds was already collected in the single-pass above.
        let cutoffDate = calendar.date(byAdding: .hour, value: -72, to: now) ?? now
        let cutoffDateStr = Self.dateFormatter.string(from: cutoffDate)
        var recentModelIds = todayModelIds
        if let cache = statsCache {
            for entry in cache.dailyModelTokens where entry.date >= cutoffDateStr {
                for (modelId, tokens) in entry.tokensByModel where tokens > 0 {
                    recentModelIds.insert(modelId)
                }
            }
        }

        // All-time mode: stats cache + uncached JSONL
        var modelTokensMap: [String: (input: Int, output: Int, cacheRead: Int, cacheWrite: Int)] = [:]
        if let cache = statsCache {
            for (modelId, usage) in cache.modelUsage where recentModelIds.contains(modelId) {
                modelTokensMap[modelId] = (
                    input: usage.inputTokens,
                    output: usage.outputTokens,
                    cacheRead: usage.cacheReadInputTokens,
                    cacheWrite: usage.cacheCreationInputTokens
                )
            }
        }

        // todayEntries all have timestamp >= today, so their date string is always todayDate.
        // A single set-membership check replaces per-entry DateFormatter calls.
        let todayIsCached = cachedDates.contains(todayDate)
        let uncachedEntries = todayIsCached ? [] : todayEntries
        for entry in uncachedEntries {
            let existing = modelTokensMap[entry.model] ?? (0, 0, 0, 0)
            modelTokensMap[entry.model] = (
                input: existing.input + entry.inputTokens,
                output: existing.output + entry.outputTokens,
                cacheRead: existing.cacheRead + entry.cacheReadTokens,
                cacheWrite: existing.cacheWrite + entry.cacheWriteTokens
            )
        }

        let modelTokens = Self.buildModelTokens(from: modelTokensMap)

        // Peak hour
        let peakEntry = statsCache?.hourCounts.max(by: { $0.value < $1.value })
        let peakHour = peakEntry.flatMap { Int($0.key) }
        let peakHourCount = peakEntry?.value ?? 0

        // First session date
        let firstSessionDate = statsCache?.firstSessionDate
            .flatMap { Self.isoFormatter.date(from: $0) }

        // Token health assessment — single-pass grouping for current + top sessions
        let healthResult = TokenHealthMonitor.shared.assessSessions(entries: allEntries, topLimit: 5, idleCutoffMinutes: idleSessionMinutes)
        let tokenHealth = healthResult.current
        let topSessionHealths = healthResult.top

        // Merge today's live JSONL data into dailyActivity so the 7D chart
        // reflects current-day usage even when stats-cache hasn't been rebuilt.
        var activity = statsCache?.dailyActivity ?? []
        if todayMessages > 0 {
            if let idx = activity.firstIndex(where: { $0.date == todayDate }) {
                // Replace if JSONL has more messages than stale cache entry
                if todayMessages > activity[idx].messageCount {
                    activity[idx] = DailyActivity(
                        date: todayDate,
                        messageCount: todayMessages,
                        sessionCount: todaySessions,
                        toolCallCount: max(todayToolCalls, activity[idx].toolCallCount)
                    )
                }
            } else {
                activity.append(DailyActivity(
                    date: todayDate,
                    messageCount: todayMessages,
                    sessionCount: todaySessions,
                    toolCallCount: todayToolCalls
                ))
            }
        }

        let snapshot = UsageSnapshot(
            lastUpdated: now,
            rateLimits: rateLimits,
            firstSessionDate: firstSessionDate,
            totalSessions: (statsCache?.totalSessions ?? 0) + todaySessions,
            totalMessages: (statsCache?.totalMessages ?? 0) + todayMessages,
            longestSessionDuration: statsCache?.longestSession?.durationFormatted,
            longestSessionMessages: statsCache?.longestSession?.messageCount ?? 0,
            peakHour: peakHour,
            peakHourCount: peakHourCount,
            todayMessages: todayMessages,
            todaySessions: todaySessions,
            todayToolCalls: todayToolCalls,
            modelTokens: modelTokens,
            totalTokens: modelTokens.reduce(0) { $0 + $1.totalTokens },
            dailyActivity: activity,
            dailyAverage: UsageSnapshot.computeDailyAverage(activity),
            trendDirection: UsageSnapshot.computeTrendDirection(activity),
            busiestDayOfWeek: UsageSnapshot.computeBusiestDay(activity),
            hourCounts: statsCache?.hourCounts ?? [:],
            tokenHealth: tokenHealth,
            topSessionHealths: topSessionHealths
        )

        // Cache the result and fingerprint
        cachedSnapshot = snapshot
        lastEntryCount = allEntries.count
        lastStatsCacheModDate = statsCacheModDate
        lastRateLimits = rateLimits
        lastIdleSessionMinutes = idleSessionMinutes

        return snapshot
    }

    /// Filter to Claude models, map to summaries, sort by total tokens descending.
    private static func buildModelTokens(
        from map: [String: (input: Int, output: Int, cacheRead: Int, cacheWrite: Int)]
    ) -> [ModelTokenSummary] {
        map.compactMap { modelId, tokens in
            guard modelId.hasPrefix("claude-") else { return nil }
            return ModelTokenSummary(
                id: modelId,
                displayName: ModelNameMapper.displayName(for: modelId),
                inputTokens: tokens.input,
                outputTokens: tokens.output,
                cacheReadTokens: tokens.cacheRead,
                cacheWriteTokens: tokens.cacheWrite
            )
        }.sorted { $0.totalTokens > $1.totalTokens }
    }

}
