import Foundation

final class UsageAggregator {
    private let statsCacheReader: StatsCacheReader
    private let sessionLogReader: SessionLogReader

    init(statsCacheReader: StatsCacheReader = .shared, sessionLogReader: SessionLogReader = .shared) {
        self.statsCacheReader = statsCacheReader
        self.sessionLogReader = sessionLogReader
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    func aggregate(rateLimits: RateLimitUsage?) -> UsageSnapshot {
        let statsCache = statsCacheReader.read()

        // Single JSONL scan — entries are already cached by SessionLogReader.
        let allEntries = sessionLogReader.readAllUsageEntries()

        // Token window: 0 = all time, 1–7 = that many days
        let tokenWindowDays = Int(UserDefaults.standard.double(forKey: UserDefaultsKeys.tokenWindowDays))

        // Single-pass filter: extract today's entries and windowed entries simultaneously.
        // Since allEntries is sorted by timestamp, we can iterate once and bucket efficiently.
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let windowStart: Date? = tokenWindowDays > 0
            ? calendar.date(byAdding: .day, value: -tokenWindowDays, to: now)
            : nil

        var todayEntries: [AssistantUsageEntry] = []
        var windowedMap: [String: (input: Int, output: Int, cacheRead: Int, cacheWrite: Int)] = [:]
        var todayModelIds = Set<String>()

        for entry in allEntries {
            if entry.timestamp >= today {
                todayEntries.append(entry)
                todayModelIds.insert(entry.model)
            }
            if let ws = windowStart, entry.timestamp >= ws {
                let existing = windowedMap[entry.model] ?? (0, 0, 0, 0)
                windowedMap[entry.model] = (
                    input: existing.input + entry.inputTokens,
                    output: existing.output + entry.outputTokens,
                    cacheRead: existing.cacheRead + entry.cacheReadTokens,
                    cacheWrite: existing.cacheWrite + entry.cacheWriteTokens
                )
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

        let modelTokens: [ModelTokenSummary]

        if tokenWindowDays > 0 {
            // Windowed mode: windowedMap was already built in the single-pass above
            modelTokens = windowedMap
                .filter { modelId, _ in modelId.hasPrefix("claude-") }
                .map { modelId, tokens in
                    ModelTokenSummary(
                        id: modelId,
                        displayName: ModelNameMapper.displayName(for: modelId),
                        inputTokens: tokens.input,
                        outputTokens: tokens.output,
                        cacheReadTokens: tokens.cacheRead,
                        cacheWriteTokens: tokens.cacheWrite
                    )
                }.sorted { $0.totalTokens > $1.totalTokens }
        } else {
            // All-time mode: stats cache + uncached JSONL (original behavior)
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

            modelTokens = modelTokensMap
                .filter { modelId, _ in modelId.hasPrefix("claude-") }
                .map { modelId, tokens in
                    ModelTokenSummary(
                        id: modelId,
                        displayName: ModelNameMapper.displayName(for: modelId),
                        inputTokens: tokens.input,
                        outputTokens: tokens.output,
                        cacheReadTokens: tokens.cacheRead,
                        cacheWriteTokens: tokens.cacheWrite
                    )
                }.sorted { $0.totalTokens > $1.totalTokens }
        }

        // Peak hour
        let peakEntry = statsCache?.hourCounts.max(by: { $0.value < $1.value })
        let peakHour = peakEntry.flatMap { Int($0.key) }
        let peakHourCount = peakEntry?.value ?? 0

        // First session date
        let firstSessionDate = statsCache?.firstSessionDate
            .flatMap { Self.isoFormatter.date(from: $0) }

        // Token health assessment — single-pass grouping for current + top sessions
        let healthResult = TokenHealthMonitor.shared.assessSessions(entries: allEntries, topLimit: 5)
        let tokenHealth = healthResult.current
        let topSessionHealths = healthResult.top

        let activity = statsCache?.dailyActivity ?? []

        return UsageSnapshot(
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
    }

}
