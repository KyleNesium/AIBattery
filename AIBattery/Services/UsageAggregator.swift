import Foundation

final class UsageAggregator: @unchecked Sendable {
    /// Side effects that must be applied on @MainActor after aggregate returns.
    struct SideEffects: Sendable {
        let activeUserModel: String?
        let observedModels: [String]
        let accountId: String?
    }

    /// Result of aggregate — snapshot + deferred side effects for @MainActor callers.
    private(set) var lastSideEffects: SideEffects?

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

    /// Per-project per-model token accumulator used by unified pass and buildProjectTokensFromMap.
    fileprivate struct ProjectAccum {
        var displayName: String
        var byModel: [String: (input: Int, output: Int, cacheRead: Int, cacheWrite: Int)] = [:]
    }

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
        let allEntries = sessionLogReader.readAllUsageEntries()

        // Side effects deferred to caller (RateLimitFetcher is @MainActor):
        // - activeUserModel = allEntries.last?.model
        // - setObservedModels(observedModels, accountId:)

        // Unified single-pass over allEntries: date grouping, today extraction,
        // project token accumulation, and windowed model token bucketing — all in one iteration.
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let todayDate = Self.dateFormatter.string(from: now)
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        let twelveMonthsAgo = calendar.date(byAdding: .month, value: -12, to: today) ?? today

        var todayEntries: [AssistantUsageEntry] = []
        var entriesByDate: [String: (messages: Int, sessions: Set<String>)] = [:]
        var jsonlTodayToolCalls = 0

        // Project accumulators (keyed by cwd → model → tokens)
        var projectMap: [String: ProjectAccum] = [:]

        // Tracks the most-recent timestamp seen for each model ID — used to build
        // the dynamic probe list in RateLimitFetcher after the pass completes.
        var lastSeenByModel: [String: Date] = [:]

        // Windowed model token accumulators
        typealias TokenMap = [String: (input: Int, output: Int, cacheRead: Int, cacheWrite: Int)]
        var todayTokenMap: TokenMap = [:]
        var weekTokenMap: TokenMap = [:]
        var monthTokenMap: TokenMap = [:]

        // Date key cache — consecutive entries usually share the same day
        var lastDay: Date?
        var lastDateKey: String = ""

        for entry in allEntries {
            let ts = entry.timestamp

            // --- Date grouping ---
            let entryDay = calendar.startOfDay(for: ts)
            let dateKey: String
            if entryDay == lastDay {
                dateKey = lastDateKey
            } else {
                dateKey = Self.dateFormatter.string(from: ts)
                lastDay = entryDay
                lastDateKey = dateKey
            }

            var bucket = entriesByDate[dateKey] ?? (messages: 0, sessions: [])
            bucket.messages += 1
            bucket.sessions.insert(entry.sessionId)
            entriesByDate[dateKey] = bucket

            // Track most-recent timestamp per model (entries are sorted ascending,
            // so last write wins — no comparison needed).
            lastSeenByModel[entry.model] = ts

            if ts >= today {
                todayEntries.append(entry)
                jsonlTodayToolCalls += entry.toolCallCount
            }

            // --- Project accumulation ---
            if entry.model.hasPrefix("claude-") {
                let projKey: String
                let projName: String
                if let cwd = entry.cwd, !cwd.isEmpty {
                    projKey = cwd
                    projName = (cwd as NSString).lastPathComponent
                } else {
                    projKey = "Other"
                    projName = "Other"
                }
                var proj = projectMap[projKey] ?? ProjectAccum(displayName: projName)
                var m = proj.byModel[entry.model] ?? (0, 0, 0, 0)
                m.input += entry.inputTokens
                m.output += entry.outputTokens
                m.cacheRead += entry.cacheReadTokens
                m.cacheWrite += entry.cacheWriteTokens
                proj.byModel[entry.model] = m
                projectMap[projKey] = proj
            }

            // --- Windowed model tokens ---
            if ts >= today {
                let e = todayTokenMap[entry.model] ?? (0, 0, 0, 0)
                todayTokenMap[entry.model] = (e.input + entry.inputTokens, e.output + entry.outputTokens,
                                              e.cacheRead + entry.cacheReadTokens, e.cacheWrite + entry.cacheWriteTokens)
                let w = weekTokenMap[entry.model] ?? (0, 0, 0, 0)
                weekTokenMap[entry.model] = (w.input + entry.inputTokens, w.output + entry.outputTokens,
                                             w.cacheRead + entry.cacheReadTokens, w.cacheWrite + entry.cacheWriteTokens)
                let mn = monthTokenMap[entry.model] ?? (0, 0, 0, 0)
                monthTokenMap[entry.model] = (mn.input + entry.inputTokens, mn.output + entry.outputTokens,
                                              mn.cacheRead + entry.cacheReadTokens, mn.cacheWrite + entry.cacheWriteTokens)
            } else if ts >= sevenDaysAgo {
                let w = weekTokenMap[entry.model] ?? (0, 0, 0, 0)
                weekTokenMap[entry.model] = (w.input + entry.inputTokens, w.output + entry.outputTokens,
                                             w.cacheRead + entry.cacheReadTokens, w.cacheWrite + entry.cacheWriteTokens)
                if ts >= twelveMonthsAgo {
                    let mn = monthTokenMap[entry.model] ?? (0, 0, 0, 0)
                    monthTokenMap[entry.model] = (mn.input + entry.inputTokens, mn.output + entry.outputTokens,
                                                  mn.cacheRead + entry.cacheReadTokens, mn.cacheWrite + entry.cacheWriteTokens)
                }
            } else if ts >= twelveMonthsAgo {
                let mn = monthTokenMap[entry.model] ?? (0, 0, 0, 0)
                monthTokenMap[entry.model] = (mn.input + entry.inputTokens, mn.output + entry.outputTokens,
                                              mn.cacheRead + entry.cacheReadTokens, mn.cacheWrite + entry.cacheWriteTokens)
            }
        }

        // Build observed model list sorted by recency (most recent first) for dynamic probe fallback.
        let observedModels = lastSeenByModel.sorted { $0.value > $1.value }.map(\.key)

        let todayMessages = todayEntries.count
        let todaySessions = entriesByDate[todayDate]?.sessions.count ?? 0
        let statsCacheToolCalls = statsCache?.dailyActivity
            .first(where: { $0.date == todayDate })?.toolCallCount ?? 0
        let todayToolCalls = max(jsonlTodayToolCalls, statsCacheToolCalls)

        // Build project tokens from accumulated map (O(projects × models) pricing lookups)
        let projectTokens = Self.buildProjectTokensFromMap(projectMap)

        // Build windowed model tokens from accumulated maps
        let todayModelTokens = Self.buildModelTokens(from: todayTokenMap)
        let weekModelTokens = Self.buildModelTokens(from: weekTokenMap)
        let monthModelTokens = Self.buildModelTokens(from: monthTokenMap)

        // All-time model tokens: stats cache + uncached JSONL
        let cachedDates = Set(statsCache?.dailyModelTokens.map(\.date) ?? [])
        var modelTokensMap: TokenMap = [:]
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
        let todayIsCached = cachedDates.contains(todayDate)
        if !todayIsCached {
            for entry in todayEntries {
                let existing = modelTokensMap[entry.model] ?? (0, 0, 0, 0)
                modelTokensMap[entry.model] = (
                    input: existing.input + entry.inputTokens,
                    output: existing.output + entry.outputTokens,
                    cacheRead: existing.cacheRead + entry.cacheReadTokens,
                    cacheWrite: existing.cacheWrite + entry.cacheWriteTokens
                )
            }
        }
        let rawModelTokens = Self.buildModelTokens(from: modelTokensMap)

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
            let toolCalls = (date == todayDate) ? jsonlTodayToolCalls : 0
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
            todayModelTokens: todayModelTokens,
            weekModelTokens: weekModelTokens,
            monthModelTokens: monthModelTokens,
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

        // Store side effects for @MainActor callers to apply
        lastSideEffects = SideEffects(
            activeUserModel: allEntries.last?.model,
            observedModels: observedModels,
            accountId: accountId
        )

        return snapshot
    }

    /// Group JSONL entries by project (full cwd path as key), compute cost per (project, model) pair.
    /// Batches pricing lookups to O(projects × models) instead of O(entries) lock acquisitions.
    /// Entries without cwd are grouped under "Other". JSONL-only — stats-cache lacks per-entry cwd.
    /// Build project token summaries from pre-accumulated map (populated in unified pass).
    /// Cost computed once per (project, model) pair — O(projects × models) pricing lookups.
    private static func buildProjectTokensFromMap(_ projectMap: [String: ProjectAccum]) -> [ProjectTokenSummary] {
        projectMap.map { key, proj in
            var totalInput = 0, totalOutput = 0, totalCacheRead = 0, totalCacheWrite = 0
            var totalCost: Double = 0
            for (modelId, tokens) in proj.byModel {
                totalInput += tokens.input
                totalOutput += tokens.output
                totalCacheRead += tokens.cacheRead
                totalCacheWrite += tokens.cacheWrite
                if let pricing = ModelPricing.pricing(for: modelId) {
                    totalCost += pricing.cost(
                        input: tokens.input, output: tokens.output,
                        cacheRead: tokens.cacheRead, cacheWrite: tokens.cacheWrite
                    )
                }
            }
            return ProjectTokenSummary(
                id: key,
                projectName: proj.displayName,
                inputTokens: totalInput,
                outputTokens: totalOutput,
                cacheReadTokens: totalCacheRead,
                cacheWriteTokens: totalCacheWrite,
                estimatedCost: totalCost
            )
        }.sorted { $0.totalTokens > $1.totalTokens }
    }

    private static func buildModelTokens(
        from map: [String: (input: Int, output: Int, cacheRead: Int, cacheWrite: Int)]
    ) -> [ModelTokenSummary] {
        map.compactMap { modelId, tokens in
            guard modelId.hasPrefix("claude-") else { return nil }
            let cost = ModelPricing.pricing(for: modelId)?.cost(
                input: tokens.input, output: tokens.output,
                cacheRead: tokens.cacheRead, cacheWrite: tokens.cacheWrite
            ) ?? 0
            return ModelTokenSummary(
                id: modelId,
                displayName: ModelNameMapper.displayName(for: modelId),
                inputTokens: tokens.input,
                outputTokens: tokens.output,
                cacheReadTokens: tokens.cacheRead,
                cacheWriteTokens: tokens.cacheWrite,
                estimatedCost: cost
            )
        }.sorted { $0.totalTokens > $1.totalTokens }
    }

}
