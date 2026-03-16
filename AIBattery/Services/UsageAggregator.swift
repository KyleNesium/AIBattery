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
    private var lastStatsCacheModDate: Date?
    private var lastRateLimits: RateLimitUsage?
    private var lastIdleSessionMinutes: Int = -1
    private var lastAccountId: String?

    /// Clear cached snapshot so the next aggregate() re-computes from scratch.
    /// Called by FileWatcher when JSONL or stats-cache files change.
    func invalidate() {
        cachedSnapshot = nil
    }

    func aggregate(rateLimits: RateLimitUsage?, accountId: String? = nil) -> UsageSnapshot {
        // Idle session cutoff for context health (0 = never hide)
        let idleSessionMinutes = Int(UserDefaults.standard.double(forKey: UserDefaultsKeys.idleSessionMinutes))

        // Check cheap fingerprints BEFORE expensive JSONL scan.
        // Only rate limits and settings can change without a file change;
        // SessionLogReader's cache is invalidated by FileWatcher, so entry count
        // only changes after invalidation (which clears our cached snapshot via
        // the file watcher callback resetting the ViewModel).
        let statsCacheModDate = statsCacheReader.lastModificationDate
        if let cached = cachedSnapshot,
           statsCacheModDate == lastStatsCacheModDate,
           rateLimits == lastRateLimits,
           idleSessionMinutes == lastIdleSessionMinutes,
           accountId == lastAccountId {
            return cached
        }

        let statsCache = statsCacheReader.read()

        // Single JSONL scan — entries are already cached by SessionLogReader.
        let allEntries = sessionLogReader.readAllUsageEntries()

        // Single-pass grouping: bucket all entries by date, collect today's separately.
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let todayDate = Self.dateFormatter.string(from: now)

        var todayEntries: [AssistantUsageEntry] = []
        var entriesByDate: [String: (messages: Int, sessions: Set<String>)] = [:]

        // Cache last date key — consecutive entries usually share the same day,
        // avoiding 90%+ of DateFormatter.string(from:) calls (expensive: locale + calendar).
        var lastDay: Date?
        var lastDateKey: String = ""

        for entry in allEntries {
            let entryDay = calendar.startOfDay(for: entry.timestamp)
            let dateKey: String
            if entryDay == lastDay {
                dateKey = lastDateKey
            } else {
                dateKey = Self.dateFormatter.string(from: entry.timestamp)
                lastDay = entryDay
                lastDateKey = dateKey
            }

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

        let rawModelTokens = Self.buildModelTokens(from: modelTokensMap)
        let projectTokens = Self.buildProjectTokens(from: allEntries)

        // Merge with persistent ledger — preserves high-water marks across stats-cache rebuilds.
        let modelTokens: [ModelTokenSummary]
        if let accountId {
            modelTokens = TokenLedger.shared.merge(rawModelTokens, accountId: accountId)
        } else {
            modelTokens = rawModelTokens
        }

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
        // Dictionary index for O(1) lookup instead of O(n) firstIndex(where:).
        // Uses uniquingKeysWith to handle corrupt stats-cache with duplicate dates
        // (Dictionary(uniqueKeysWithValues:) would fatally trap on duplicates).
        var activityIndex: [String: Int] = Dictionary(
            activity.enumerated().map { ($1.date, $0) },
            uniquingKeysWith: { _, last in last }
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

        // Sort by date so dailyActivity.last is the most recent day.
        // Stats-cache entries are pre-sorted, but JSONL-only days are appended
        // in arbitrary dictionary iteration order.
        activity.sort { $0.date < $1.date }

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
            projectTokens: projectTokens,
            totalTokens: modelTokens.reduce(0) { $0 + $1.totalTokens },
            totalProjectTokens: projectTokens.reduce(0) { $0 + $1.totalTokens },
            totalProjectCost: projectTokens.reduce(0.0) { $0 + $1.estimatedCost },
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
        lastStatsCacheModDate = statsCacheModDate
        lastRateLimits = rateLimits
        lastIdleSessionMinutes = idleSessionMinutes
        lastAccountId = accountId

        return snapshot
    }

    /// Group JSONL entries by project (full cwd path as key), compute per-entry cost.
    /// Entries without cwd are grouped under "Other". JSONL-only — stats-cache lacks per-entry cwd.
    private static func buildProjectTokens(from entries: [AssistantUsageEntry]) -> [ProjectTokenSummary] {
        struct Accumulator {
            var displayName: String
            var input: Int = 0
            var output: Int = 0
            var cacheRead: Int = 0
            var cacheWrite: Int = 0
            var cost: Double = 0
        }

        var byProject: [String: Accumulator] = [:]
        for entry in entries {
            guard entry.model.hasPrefix("claude-") else { continue }

            let key: String
            let displayName: String
            if let cwd = entry.cwd, !cwd.isEmpty {
                key = cwd
                displayName = (cwd as NSString).lastPathComponent
            } else {
                key = "Other"
                displayName = "Other"
            }

            var acc = byProject[key] ?? Accumulator(displayName: displayName)
            acc.input += entry.inputTokens
            acc.output += entry.outputTokens
            acc.cacheRead += entry.cacheReadTokens
            acc.cacheWrite += entry.cacheWriteTokens
            if let pricing = ModelPricing.pricing(for: entry.model) {
                acc.cost += pricing.cost(
                    input: entry.inputTokens,
                    output: entry.outputTokens,
                    cacheRead: entry.cacheReadTokens,
                    cacheWrite: entry.cacheWriteTokens
                )
            }
            byProject[key] = acc
        }

        return byProject.map { key, acc in
            ProjectTokenSummary(
                id: key,
                projectName: acc.displayName,
                inputTokens: acc.input,
                outputTokens: acc.output,
                cacheReadTokens: acc.cacheRead,
                cacheWriteTokens: acc.cacheWrite,
                estimatedCost: acc.cost
            )
        }.sorted { $0.totalTokens > $1.totalTokens }
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
