import Foundation

final class UsageAggregator: @unchecked Sendable {
    /// Side effects that must be applied on @MainActor after aggregate returns.
    struct SideEffects {
        let activeUserModel: String?
        let observedModels: [String]
        let accountId: String?
    }

    private let statsCacheReader: StatsCacheReader
    private let sessionLogReader: SessionLogReader
    /// Guards all mutable cached state — prevents concurrent Task.detached calls
    /// from racing on cachedSnapshot, lastRateLimits, etc.
    private let lock = NSLock()

    init(statsCacheReader: StatsCacheReader, sessionLogReader: SessionLogReader) {
        self.statsCacheReader = statsCacheReader
        self.sessionLogReader = sessionLogReader
    }

    convenience init() {
        self.init(statsCacheReader: .shared, sessionLogReader: .shared)
    }

    private static let dateFormatter = DateFormatters.dateKey
    nonisolated(unsafe) private static let isoFormatter = DateFormatters.iso8601

    // MARK: - Time window constants

    /// 5-hour sliding window for rate limit estimation (seconds).
    private static let fiveHourWindow: TimeInterval = 5 * 3_600
    /// 7-day sliding window for rate limit estimation (seconds).
    /// Rolling 7×86400 to mirror Anthropic's actual quota window — distinct from
    /// the calendar-day "last 7 days" boundary used for the per-model weekly
    /// breakdown (`weekTokenMap`), which intentionally aligns to local day
    /// boundaries because the UI breakdown is a chart, not a quota signal.
    private static let sevenDayWindow: TimeInterval = 7 * 86_400
    /// 24-hour trailing window for chart display (seconds).
    private static let twentyFourHourWindow: TimeInterval = 86_400
    /// Number of 15-minute buckets in the 5-hour insights chart.
    private static let fiveHourBucketCount = 20
    /// Duration of each insights chart bucket (seconds).
    private static let bucketDuration: TimeInterval = 900

    /// Per-model token accumulator: input, output, cacheRead, cacheWrite.
    private typealias TokenMap = [String: (input: Int, output: Int, cacheRead: Int, cacheWrite: Int)]

    /// Accumulate an entry's tokens into a per-model map.
    private static func accumulate(into map: inout TokenMap, key: String, entry: AssistantUsageEntry) {
        let e = map[key] ?? (0, 0, 0, 0)
        map[key] = (e.input + entry.inputTokens, e.output + entry.outputTokens,
                    e.cacheRead + entry.cacheReadTokens, e.cacheWrite + entry.cacheWriteTokens)
    }

    /// Merge pre-accumulated token totals into a per-model map.
    private static func accumulate(into map: inout TokenMap, key: String, tokens: TokenMap.Value) {
        let e = map[key] ?? (0, 0, 0, 0)
        map[key] = (e.input + tokens.input, e.output + tokens.output,
                    e.cacheRead + tokens.cacheRead, e.cacheWrite + tokens.cacheWrite)
    }

    /// Per-project per-model token accumulator used by unified pass and buildProjectTokensFromMap.
    fileprivate struct ProjectAccum {
        var displayName: String
        var byModel: [String: (input: Int, output: Int, cacheRead: Int, cacheWrite: Int)] = [:]
    }

    // MARK: - Redundant aggregation skip

    private var cachedSnapshot: UsageSnapshot?
    private var cachedEffects: SideEffects?
    private var lastStatsCacheModDate: Date?
    private var lastRateLimits: RateLimitUsage?
    private var lastStandardLimits: StandardRateLimits?
    private var lastRateLimitSource: RateLimitSource?
    private var lastIdleSessionMinutes: Int = -1
    private var lastAccountId: String?

    /// Clear cached snapshot so the next aggregate() re-computes from scratch.
    /// Called by FileWatcher when JSONL or stats-cache files change.
    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        cachedSnapshot = nil
    }

    func aggregate(
        rateLimits: RateLimitUsage?,
        rateLimitSource: RateLimitSource? = nil,
        standardLimits: StandardRateLimits? = nil,
        accountId: String? = nil,
        now: Date = Date()
    ) -> (UsageSnapshot, SideEffects) {
        // Idle session cutoff for context health (0 = never hide)
        let idleSessionMinutes = Int(UserDefaults.standard.double(forKey: UserDefaultsKeys.idleSessionMinutes))

        // Narrow lock scope: only guards cached-state reads/writes, not I/O.
        // Prevents blocking invalidate() callers on main actor during JSONL scans.
        lock.lock()
        let statsCacheModDate = statsCacheReader.lastModificationDate
        if let cached = cachedSnapshot,
           statsCacheModDate == lastStatsCacheModDate,
           rateLimits == lastRateLimits,
           standardLimits == lastStandardLimits,
           rateLimitSource == lastRateLimitSource,
           idleSessionMinutes == lastIdleSessionMinutes,
           accountId == lastAccountId {
            let effects = cachedEffects ?? SideEffects(activeUserModel: nil, observedModels: [], accountId: accountId)
            lock.unlock()
            return (cached, effects)
        }
        lock.unlock()

        // Expensive I/O runs without holding the lock.
        let statsCache = statsCacheReader.read()
        let allEntries = sessionLogReader.readAllUsageEntries()

        // Side effects deferred to caller (RateLimitFetcher is @MainActor):
        // - activeUserModel = allEntries.last?.model
        // - setObservedModels(observedModels, accountId:)

        // Unified single-pass over allEntries: date grouping, today extraction,
        // project token accumulation, and windowed model token bucketing — all in one iteration.
        // `now` is injectable via the function parameter; default = Date(). Tests
        // pin window-boundary behavior by supplying a deterministic value.
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let todayDate = Self.dateFormatter.string(from: now)
        let fiveHoursAgo = now.addingTimeInterval(-Self.fiveHourWindow)
        let twentyFourHoursAgo = now.addingTimeInterval(-Self.twentyFourHourWindow)
        // Rolling 7×86400 boundary for the rate-limit token count (mirrors
        // Anthropic's actual sliding-window quota). Distinct from `sevenDaysAgo`
        // below, which is calendar-day for the per-model weekly UI breakdown.
        let sevenDayRateLimitCutoff = now.addingTimeInterval(-Self.sevenDayWindow)
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        let twelveMonthsAgo = calendar.date(byAdding: .month, value: -12, to: today) ?? today

        var todayEntries: [AssistantUsageEntry] = []
        var trailing24hEntries: [AssistantUsageEntry] = []
        // 5-hour and 7-day token totals for local usage estimation
        var fiveHourTokens = 0
        var sevenDayTokens = 0
        // 5-hour 15-minute token buckets for the insights chart (bucket 0 = oldest)
        var fiveHourTokenBuckets: [Int: Int] = [:]
        // Per-date token totals for 7D and 12M chart modes
        var dailyTokenTotals: [String: Int] = [:]
        var entriesByDate: [String: (messages: Int, sessions: Set<String>)] = [:]
        // All-time model tokens from JSONL entries not covered by stats-cache
        let cachedDates = Set(statsCache?.dailyModelTokens.map(\.date) ?? [])
        var uncachedModelTokensMap: TokenMap = [:]
        // All JSONL model tokens (all dates) — used as a floor for all-time totals
        // so that Projects (JSONL-only) never exceeds All Time.
        var allJsonlModelTokensMap: TokenMap = [:]
        var jsonlTodayToolCalls = 0

        // Project accumulators (keyed by cwd → model → tokens)
        var projectMap: [String: ProjectAccum] = [:]

        // Tracks the most-recent timestamp seen for each model ID — used to build
        // the dynamic probe list in RateLimitFetcher after the pass completes.
        var lastSeenByModel: [String: Date] = [:]

        // Windowed model token accumulators
        var todayTokenMap: TokenMap = [:]
        var weekTokenMap: TokenMap = [:]
        var monthTokenMap: TokenMap = [:]

        // Date boundary cache — avoids Calendar.startOfDay() ICU calls per entry.
        // Entries are sorted ascending, so we track the current day's start/end
        // and only recompute when timestamp crosses the boundary.
        var lastDayStart: Date = .distantPast
        var lastDayEnd: Date = .distantPast
        var lastDateKey = ""

        for entry in allEntries {
            let ts = entry.timestamp

            // --- Date grouping ---
            let dateKey: String
            if ts >= lastDayStart && ts < lastDayEnd {
                dateKey = lastDateKey
            } else {
                let entryDay = calendar.startOfDay(for: ts)
                lastDayStart = entryDay
                lastDayEnd = entryDay.addingTimeInterval(86_400)
                dateKey = Self.dateFormatter.string(from: ts)
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
            if ts >= twentyFourHoursAgo {
                trailing24hEntries.append(entry)
            }

            // --- 5-hour and 7-day token totals for local usage estimation ---
            // Include all token types: Anthropic's unified rate limit counts input, output,
            // cache read, and cache write tokens toward the 5h/7d budget.
            let entryAllTokens = entry.inputTokens + entry.outputTokens + entry.cacheReadTokens + entry.cacheWriteTokens
            if ts >= fiveHoursAgo {
                fiveHourTokens += entryAllTokens
                // 15-minute bucket: offset 0 = 5h ago, offset (bucketCount-1) = now
                let secondsAgo = now.timeIntervalSince(ts)
                let bucket = min(Self.fiveHourBucketCount - 1, Int((Self.fiveHourWindow - secondsAgo) / Self.bucketDuration))
                if bucket >= 0 {
                    fiveHourTokenBuckets[bucket, default: 0] += entryAllTokens
                }
            }
            if ts >= sevenDayRateLimitCutoff {
                sevenDayTokens += entryAllTokens
            }
            // Daily token totals (all dates, for 7D and 12M charts)
            // Uses all token types to match 5h/7d summary totals and model breakdowns.
            dailyTokenTotals[dateKey, default: 0] += entryAllTokens

            // All-time model tokens from dates not in stats-cache
            if !cachedDates.contains(dateKey) {
                Self.accumulate(into: &uncachedModelTokensMap, key: entry.model, entry: entry)
            }

            // Accumulate all JSONL model tokens (all dates) as a floor for all-time totals.
            if entry.model.hasPrefix("claude-") {
                Self.accumulate(into: &allJsonlModelTokensMap, key: entry.model, entry: entry)
            }

            // --- Project accumulation ---
            if entry.model.hasPrefix("claude-") {
                let projKey: String
                let projName: String
                if let cwd = entry.cwd, !cwd.isEmpty, (cwd as NSString).lastPathComponent != "/" {
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
                Self.accumulate(into: &todayTokenMap, key: entry.model, entry: entry)
                Self.accumulate(into: &weekTokenMap, key: entry.model, entry: entry)
                Self.accumulate(into: &monthTokenMap, key: entry.model, entry: entry)
            } else if ts >= sevenDaysAgo {
                Self.accumulate(into: &weekTokenMap, key: entry.model, entry: entry)
                if ts >= twelveMonthsAgo {
                    Self.accumulate(into: &monthTokenMap, key: entry.model, entry: entry)
                }
            } else if ts >= twelveMonthsAgo {
                Self.accumulate(into: &monthTokenMap, key: entry.model, entry: entry)
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
        // Add JSONL entries from dates not covered by stats-cache.
        // Uses uncachedModelTokensMap accumulated during the single-pass loop.
        for (model, tokens) in uncachedModelTokensMap {
            Self.accumulate(into: &modelTokensMap, key: model, tokens: tokens)
        }
        // Ensure all-time per-model totals are never less than JSONL-only totals.
        // Stats-cache can be stale (not rebuilt since new JSONL entries were added for
        // a cached date), which would make Projects (all JSONL) exceed All Time.
        for (model, jsonl) in allJsonlModelTokensMap {
            let existing = modelTokensMap[model] ?? (0, 0, 0, 0)
            modelTokensMap[model] = (
                input: max(existing.input, jsonl.input),
                output: max(existing.output, jsonl.output),
                cacheRead: max(existing.cacheRead, jsonl.cacheRead),
                cacheWrite: max(existing.cacheWrite, jsonl.cacheWrite)
            )
        }
        let rawModelTokens = Self.buildModelTokens(from: modelTokensMap)

        // Merge with persistent ledger — preserves high-water marks across stats-cache rebuilds.
        let modelTokens: [ModelTokenSummary] = if let accountId {
            TokenLedger.shared.merge(rawModelTokens, accountId: accountId)
        } else {
            rawModelTokens
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

        // Build trailing 24-hour breakdown from JSONL (for 24H chart).
        // Uses entries from the past 24 hours (not just today) so the chart
        // correctly shows yesterday evening's activity in the morning.
        var todayHourCounts: [String: Int] = [:]
        for entry in trailing24hEntries {
            let hour = String(calendar.component(.hour, from: entry.timestamp))
            todayHourCounts[hour, default: 0] += 1
        }

        // Merge today-only JSONL into all-time hourCounts for peak hour stat.
        // Uses todayEntries (not trailing24h) to avoid inflating peaks by
        // combining yesterday + today counts for the same hour.
        var todayOnlyHourCounts: [String: Int] = [:]
        for entry in todayEntries {
            let hour = String(calendar.component(.hour, from: entry.timestamp))
            todayOnlyHourCounts[hour, default: 0] += 1
        }
        var hourCounts = statsCache?.hourCounts ?? [:]
        for (hour, count) in todayOnlyHourCounts {
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
            rateLimitSource: rateLimitSource,
            standardLimits: standardLimits,
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
            totalUsageTokens: modelTokens.reduce(0) { $0 + $1.usageTokens },
            totalProjectTokens: projectTokens.reduce(0) { $0 + $1.totalTokens },
            totalProjectUsageTokens: projectTokens.reduce(0) { $0 + $1.usageTokens },
            totalProjectCost: projectTokens.reduce(0.0) { $0 + $1.estimatedCost },
            fiveHourTokens: fiveHourTokens,
            sevenDayTokens: sevenDayTokens,
            fiveHourTokenBuckets: fiveHourTokenBuckets,
            dailyTokenTotals: dailyTokenTotals,
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

        // Build side effects for @MainActor callers to apply
        let effects = SideEffects(
            activeUserModel: allEntries.last?.model,
            observedModels: observedModels,
            accountId: accountId
        )

        // Cache the result and fingerprint (lock protects mutable state only)
        lock.lock()
        cachedSnapshot = snapshot
        cachedEffects = effects
        lastStatsCacheModDate = statsCacheModDate
        lastRateLimits = rateLimits
        lastStandardLimits = standardLimits
        lastRateLimitSource = rateLimitSource
        lastIdleSessionMinutes = idleSessionMinutes
        lastAccountId = accountId
        lock.unlock()

        return (snapshot, effects)
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

    private static func buildModelTokens(from map: TokenMap) -> [ModelTokenSummary] {
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
