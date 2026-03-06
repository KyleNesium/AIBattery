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

        // Single-pass grouping: bucket all entries by date, collect today's separately.
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let todayDate = Self.dateFormatter.string(from: now)

        var todayEntries: [AssistantUsageEntry] = []
        var entriesByDate: [String: (messages: Int, sessions: Set<String>)] = [:]

        for entry in allEntries {
            let dateKey = Self.dateFormatter.string(from: entry.timestamp)
            var bucket = entriesByDate[dateKey] ?? (messages: 0, sessions: [])
            bucket.messages += 1
            bucket.sessions.insert(entry.sessionId)
            entriesByDate[dateKey] = bucket

            if entry.timestamp >= today {
                todayEntries.append(entry)
            }
        }

        let todayMessages = todayEntries.count
        let todaySessions = Set(todayEntries.map(\.sessionId)).count
        let todayToolCalls = statsCache?.dailyActivity
            .first(where: { $0.date == todayDate })?.toolCallCount ?? 0

        // Dates already covered by stats cache
        let cachedDates = Set(statsCache?.dailyModelTokens.map(\.date) ?? [])

        // All-time mode: stats cache + uncached JSONL
        var modelTokensMap: [String: (input: Int, output: Int, cacheRead: Int, cacheWrite: Int)] = [:]
        if let cache = statsCache {
            for (modelId, usage) in cache.modelUsage {
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

        // First session date
        let firstSessionDate = statsCache?.firstSessionDate
            .flatMap { Self.isoFormatter.date(from: $0) }

        // Token health assessment — single-pass grouping for current + top sessions
        let healthResult = TokenHealthMonitor.shared.assessSessions(entries: allEntries, topLimit: 5, idleCutoffMinutes: idleSessionMinutes)
        let tokenHealth = healthResult.current
        let topSessionHealths = healthResult.top

        // Merge JSONL daily counts into dailyActivity and compute additional
        // messages/sessions beyond stats-cache in a single pass.
        var activity = statsCache?.dailyActivity ?? []
        // Dictionary index for O(1) lookup instead of O(n) firstIndex(where:)
        var activityIndex: [String: Int] = Dictionary(
            uniqueKeysWithValues: activity.enumerated().map { ($1.date, $0) }
        )
        var additionalMessages = 0
        var additionalSessions = 0
        for (date, bucket) in entriesByDate {
            let toolCalls = (date == todayDate) ? todayToolCalls : 0
            if let idx = activityIndex[date] {
                // Capture original stats-cache values before potential mutation
                let cachedMessages = activity[idx].messageCount
                let cachedSessions = activity[idx].sessionCount
                // Update existing entry if JSONL has more messages
                if bucket.messages > cachedMessages {
                    activity[idx] = DailyActivity(
                        date: date,
                        messageCount: bucket.messages,
                        sessionCount: bucket.sessions.count,
                        toolCallCount: max(toolCalls, activity[idx].toolCallCount)
                    )
                }
                additionalMessages += max(bucket.messages - cachedMessages, 0)
                additionalSessions += max(bucket.sessions.count - cachedSessions, 0)
            } else {
                activityIndex[date] = activity.count
                activity.append(DailyActivity(
                    date: date,
                    messageCount: bucket.messages,
                    sessionCount: bucket.sessions.count,
                    toolCallCount: toolCalls
                ))
                additionalMessages += bucket.messages
                additionalSessions += bucket.sessions.count
            }
        }

        // Build today's hourly breakdown from JSONL (for 12H chart).
        var todayHourCounts: [String: Int] = [:]
        for entry in todayEntries {
            let hour = String(calendar.component(.hour, from: entry.timestamp))
            todayHourCounts[hour, default: 0] += 1
        }

        // Merge today's JSONL into all-time hourCounts for peak hour stat.
        var hourCounts = statsCache?.hourCounts ?? [:]
        for (hour, count) in todayHourCounts {
            hourCounts[hour] = max(hourCounts[hour] ?? 0, count)
        }

        // Peak hour (computed after hourly merge to reflect live data)
        let peakEntry = hourCounts.max(by: { $0.value < $1.value })
        let peakHour = peakEntry.flatMap { Int($0.key) }
        let peakHourCount = peakEntry?.value ?? 0

        let activityStats = UsageSnapshot.computeActivityStats(activity)

        let snapshot = UsageSnapshot(
            lastUpdated: now,
            rateLimits: rateLimits,
            firstSessionDate: firstSessionDate,
            totalSessions: (statsCache?.totalSessions ?? 0) + additionalSessions,
            totalMessages: (statsCache?.totalMessages ?? 0) + additionalMessages,
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
            dailyAverage: activityStats.average,
            trendDirection: activityStats.trend,
            busiestDayOfWeek: activityStats.busiestDay,
            hourCounts: hourCounts,
            todayHourCounts: todayHourCounts,
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
