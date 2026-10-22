import Foundation

final class UsageAggregator: @unchecked Sendable {
    /// Side effects that must be applied on @MainActor after aggregate returns.
    struct SideEffects {
        let activeUserModel: String?
        let observedModels: [String]
        let accountId: String?
        /// Which provider's local data produced these effects. Callers only feed
        /// `activeUserModel` / `observedModels` into `RateLimitFetcher` (the Claude
        /// Messages-probe model list) when this is `.claude`.
        var provider: AIProvider = .claude
    }

    /// The two snapshots one `aggregate` call produces when attribution is active.
    struct AggregateResult {
        /// What the active account's popover shows (attributed when attribution is active).
        var detail: UsageSnapshot
        /// What the overview cards show for the provider: every entry on disk. Equal to
        /// `detail` when attribution is `.all`.
        var providerWide: UsageSnapshot
        let effects: SideEffects
    }

    /// Optional: Codex has no stats-cache equivalent — its all-time figures derive
    /// purely from session JSONL (bounded by log retention; the UI says so).
    private let statsCacheReader: StatsCacheReader?
    private let sessionLogReader: any UsageEntrySource
    /// Which provider's entries this aggregator tracks. Drives the model-ID filter
    /// (`isTrackedModel`) and is stamped onto every `UsageSnapshot` it produces.
    let provider: AIProvider
    /// Persistent high-water-mark store for all-time per-model totals. Injectable so
    /// tests don't write to the user's real `token-ledger.json` (default `.shared`).
    private let ledger: TokenLedger
    /// Guards all mutable cached state — prevents concurrent Task.detached calls
    /// from racing on cachedSnapshot, lastRateLimits, etc.
    private let lock = NSLock()

    init(
        statsCacheReader: StatsCacheReader?,
        sessionLogReader: any UsageEntrySource,
        ledger: TokenLedger = .shared,
        provider: AIProvider = .claude
    ) {
        self.statsCacheReader = statsCacheReader
        self.sessionLogReader = sessionLogReader
        self.ledger = ledger
        self.provider = provider
    }

    /// Production wiring per provider: Claude reads `~/.claude` (stats cache + JSONL);
    /// Codex reads `~/.codex/sessions` only.
    convenience init(provider: AIProvider = .claude) {
        switch provider {
        case .claude:
            self.init(statsCacheReader: .shared, sessionLogReader: SessionLogReader.shared, provider: .claude)
        case .codex:
            self.init(statsCacheReader: nil, sessionLogReader: CodexSessionLogReader.shared, provider: .codex)
        }
    }

    /// Model IDs that belong to a provider's local data. Anything else (e.g. the
    /// `"synthetic"` pseudo-model Claude Code writes, or a Claude entry that somehow
    /// lands in a Codex scan) is excluded from per-model tokens, projects and cost.
    nonisolated static func isTrackedModel(_ modelId: String, provider: AIProvider) -> Bool {
        switch provider {
        case .claude: modelId.hasPrefix("claude-")
        case .codex: modelId.hasPrefix("gpt-")
        }
    }

    private static let dateFormatter = DateFormatters.dateKey

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

    /// Per-model token accumulator: input, output, cacheRead, cacheWrite, reasoning.
    private typealias TokenMap = [String: (input: Int, output: Int, cacheRead: Int, cacheWrite: Int, reasoning: Int)]

    /// Accumulate an entry's tokens into a per-model map.
    private static func accumulate(into map: inout TokenMap, key: String, entry: AssistantUsageEntry) {
        let e = map[key] ?? (0, 0, 0, 0, 0)
        map[key] = (e.input + entry.inputTokens, e.output + entry.outputTokens,
                    e.cacheRead + entry.cacheReadTokens, e.cacheWrite + entry.cacheWriteTokens,
                    e.reasoning + entry.reasoningTokens)
    }

    /// Merge pre-accumulated token totals into a per-model map.
    private static func accumulate(into map: inout TokenMap, key: String, tokens: TokenMap.Value) {
        let e = map[key] ?? (0, 0, 0, 0, 0)
        map[key] = (e.input + tokens.input, e.output + tokens.output,
                    e.cacheRead + tokens.cacheRead, e.cacheWrite + tokens.cacheWrite,
                    e.reasoning + tokens.reasoning)
    }

    /// Per-project per-model token accumulator used by unified pass and buildProjectTokensFromMap.
    fileprivate struct ProjectAccum {
        var displayName: String
        var byModel: [String: (input: Int, output: Int, cacheRead: Int, cacheWrite: Int)] = [:]
    }

    /// One accumulation over a sorted entry stream, plus the assembly of its snapshot.
    ///
    /// Extracted from `aggregate` so that a second instance can run beside the first
    /// (per-account attribution, Task 7): the entries are read once and walked once; each
    /// instance only pays for its own accumulators.
    ///
    ///     entries ──► pass.add(entry) ×N ──► pass.finish(entries:…) ──► UsageSnapshot
    ///
    private struct AggregationPass {
        let provider: AIProvider
        let now: Date
        let calendar: Calendar
        let today: Date
        let todayDate: String
        let fiveHoursAgo: Date
        let twentyFourHoursAgo: Date
        /// Rolling 7×86400 for the rate-limit count, distinct from the calendar-day
        /// `sevenDaysAgo` used for the weekly UI breakdown.
        let sevenDayRateLimitCutoff: Date
        let sevenDaysAgo: Date
        let twelveMonthsAgo: Date
        let cachedDates: Set<String>

        var todayEntries: [AssistantUsageEntry] = []
        var trailing24hEntries: [AssistantUsageEntry] = []
        var fiveHourTokens = 0
        var sevenDayTokens = 0
        var fiveHourTokenBuckets: [Int: Int] = [:]
        var dailyTokenTotals: [String: Int] = [:]
        var entriesByDate: [String: (messages: Int, sessions: Set<String>)] = [:]
        var uncachedModelTokensMap: TokenMap = [:]
        var allJsonlModelTokensMap: TokenMap = [:]
        var jsonlTodayToolCalls = 0
        var projectMap: [String: ProjectAccum] = [:]
        /// Feeds the Claude Messages-probe model list (`SideEffects.observedModels`,
        /// sorted most-recent-first in `finish`).
        var lastSeenByModel: [String: Date] = [:]
        var todayTokenMap: TokenMap = [:]
        var weekTokenMap: TokenMap = [:]
        var monthTokenMap: TokenMap = [:]
        private var lastDayStart: Date = .distantPast
        private var lastDayEnd: Date = .distantPast
        private var lastDateKey = ""

        init(provider: AIProvider, now: Date, cachedDates: Set<String>) {
            self.provider = provider
            self.now = now
            self.cachedDates = cachedDates
            let calendar = Calendar.current
            self.calendar = calendar
            today = calendar.startOfDay(for: now)
            todayDate = UsageAggregator.dateFormatter.string(from: now)
            fiveHoursAgo = now.addingTimeInterval(-UsageAggregator.fiveHourWindow)
            twentyFourHoursAgo = now.addingTimeInterval(-UsageAggregator.twentyFourHourWindow)
            sevenDayRateLimitCutoff = now.addingTimeInterval(-UsageAggregator.sevenDayWindow)
            sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: today) ?? today
            twelveMonthsAgo = calendar.date(byAdding: .month, value: -12, to: today) ?? today
        }

        /// Entries must be fed in ascending timestamp order — the day-boundary cache
        /// (`lastDayStart`/`lastDayEnd`/`lastDateKey`) assumes a monotonically advancing
        /// stream and will mis-bucket an out-of-order entry silently.
        mutating func add(_ entry: AssistantUsageEntry) {
            let ts = entry.timestamp

            // --- Date grouping ---
            let dateKey: String
            if ts >= lastDayStart && ts < lastDayEnd {
                dateKey = lastDateKey
            } else {
                let entryDay = calendar.startOfDay(for: ts)
                lastDayStart = entryDay
                // Calendar arithmetic, not a fixed 86 400 s: on a DST spring-forward the
                // local day is 23 h, so a flat +86 400 lands an hour INTO the next day and
                // every entry in that hour reuses the previous day's key — landing on the
                // wrong 7D bar, the wrong daily total and the wrong side of
                // `changeVsYesterday`, twice a year for every user in a DST timezone.
                lastDayEnd = calendar.date(byAdding: .day, value: 1, to: entryDay) ?? entryDay.addingTimeInterval(86_400)
                dateKey = UsageAggregator.dateFormatter.string(from: ts)
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
                let bucket = min(UsageAggregator.fiveHourBucketCount - 1, Int((UsageAggregator.fiveHourWindow - secondsAgo) / UsageAggregator.bucketDuration))
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
                UsageAggregator.accumulate(into: &uncachedModelTokensMap, key: entry.model, entry: entry)
            }

            // Accumulate all JSONL model tokens (all dates) as a floor for all-time totals.
            if UsageAggregator.isTrackedModel(entry.model, provider: provider) {
                UsageAggregator.accumulate(into: &allJsonlModelTokensMap, key: entry.model, entry: entry)
            }

            // --- Project accumulation ---
            if UsageAggregator.isTrackedModel(entry.model, provider: provider) {
                // The map is keyed by the cwd itself, so a project seen earlier in this
                // pass needs no path work at all. `lastPathComponent` bridges to NSString
                // and costs about a microsecond; it used to run TWICE per entry, over
                // every entry, on every pass — for a value with only tens of distinct
                // results. Now it runs once per distinct cwd.
                var projKey = "Other"
                if let cwd = entry.cwd, !cwd.isEmpty {
                    if projectMap[cwd] != nil {
                        projKey = cwd
                    } else {
                        let name = (cwd as NSString).lastPathComponent
                        // A cwd whose last component is "/" carries no project name.
                        if name != "/" {
                            projKey = cwd
                            projectMap[cwd] = ProjectAccum(displayName: name)
                        }
                    }
                }
                var proj = projectMap[projKey] ?? ProjectAccum(displayName: "Other")
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
                UsageAggregator.accumulate(into: &todayTokenMap, key: entry.model, entry: entry)
                UsageAggregator.accumulate(into: &weekTokenMap, key: entry.model, entry: entry)
                UsageAggregator.accumulate(into: &monthTokenMap, key: entry.model, entry: entry)
            } else if ts >= sevenDaysAgo {
                UsageAggregator.accumulate(into: &weekTokenMap, key: entry.model, entry: entry)
                if ts >= twelveMonthsAgo {
                    UsageAggregator.accumulate(into: &monthTokenMap, key: entry.model, entry: entry)
                }
            } else if ts >= twelveMonthsAgo {
                UsageAggregator.accumulate(into: &monthTokenMap, key: entry.model, entry: entry)
            }
        }

        /// Everything after the loop: observed models, project/model summaries, ledger
        /// merge, health, activity merge, hour counts, and the snapshot itself.
        ///
        /// `entries` need not be the same array that was fed to `add` — it supplies the
        /// stream `finish` reads itself from (first-session date, session health), so a
        /// caller running the provider-wide and per-account passes side by side can feed
        /// each its own subset while sharing accumulation of the same underlying scan.
        func finish(
            entries: [AssistantUsageEntry],
            statsCache: StatsCache?,
            rateLimits: RateLimitUsage?,
            rateLimitSource: RateLimitSource?,
            standardLimits: StandardRateLimits?,
            rateLimitsFresh: Bool,
            idleSessionMinutes: Int,
            ledger: TokenLedger,
            ledgerKey: String?
        ) -> (snapshot: UsageSnapshot, observedModels: [String]) {
            // Build observed model list sorted by recency (most recent first) for dynamic probe fallback.
            let observedModels = lastSeenByModel.sorted { $0.value > $1.value }.map(\.key)

            let todayMessages = todayEntries.count
            let todaySessions = entriesByDate[todayDate]?.sessions.count ?? 0
            let statsCacheToolCalls = statsCache?.dailyActivity
                .first(where: { $0.date == todayDate })?.toolCallCount ?? 0
            let todayToolCalls = max(jsonlTodayToolCalls, statsCacheToolCalls)

            // Build project tokens from accumulated map (O(projects × models) pricing lookups)
            let projectTokens = UsageAggregator.buildProjectTokensFromMap(projectMap)

            // Build windowed model tokens from accumulated maps
            let todayModelTokens = UsageAggregator.buildModelTokens(from: todayTokenMap, provider: provider)
            let weekModelTokens = UsageAggregator.buildModelTokens(from: weekTokenMap, provider: provider)
            let monthModelTokens = UsageAggregator.buildModelTokens(from: monthTokenMap, provider: provider)

            // All-time model tokens: stats cache + uncached JSONL
            var modelTokensMap: TokenMap = [:]
            if let cache = statsCache {
                for (modelId, usage) in cache.modelUsage {
                    modelTokensMap[modelId] = (
                        input: usage.inputTokens,
                        output: usage.outputTokens,
                        cacheRead: usage.cacheReadInputTokens,
                        cacheWrite: usage.cacheCreationInputTokens,
                        reasoning: 0
                    )
                }
            }
            // Add JSONL entries from dates not covered by stats-cache.
            // Uses uncachedModelTokensMap accumulated during the single-pass loop.
            for (model, tokens) in uncachedModelTokensMap {
                UsageAggregator.accumulate(into: &modelTokensMap, key: model, tokens: tokens)
            }
            // Ensure all-time per-model totals are never less than JSONL-only totals.
            // Stats-cache can be stale (not rebuilt since new JSONL entries were added for
            // a cached date), which would make Projects (all JSONL) exceed All Time.
            for (model, jsonl) in allJsonlModelTokensMap {
                let existing = modelTokensMap[model] ?? (0, 0, 0, 0, 0)
                modelTokensMap[model] = (
                    input: max(existing.input, jsonl.input),
                    output: max(existing.output, jsonl.output),
                    cacheRead: max(existing.cacheRead, jsonl.cacheRead),
                    cacheWrite: max(existing.cacheWrite, jsonl.cacheWrite),
                    reasoning: max(existing.reasoning, jsonl.reasoning)
                )
            }
            let rawModelTokens = UsageAggregator.buildModelTokens(from: modelTokensMap, provider: provider)

            // Merge with persistent ledger — preserves high-water marks across stats-cache rebuilds.
            let modelTokens: [ModelTokenSummary]
            var ledgerSince: Date?
            if let ledgerKey {
                modelTokens = ledger.merge(rawModelTokens, ledgerKey: ledgerKey)
                // Codex has no lifetime cache of its own — date its All-Time figure from
                // the ledger's first scan. Claude's firstSessionDate already covers this.
                if provider == .codex {
                    ledgerSince = ledger.firstScanDate(ledgerKey: ledgerKey)
                }
            } else {
                modelTokens = rawModelTokens
            }

            // First session date — stats cache when present, else the earliest JSONL entry
            // (entries are sorted ascending). Codex always takes the fallback.
            let firstSessionDate = statsCache?.firstSessionDate
                .flatMap(DateFormatters.parseISO8601)
                ?? entries.first?.timestamp

            // Token health assessment — single-pass grouping for current + top sessions
            let healthResult = TokenHealthMonitor.shared.assessSessions(entries: entries, topLimit: 5, idleCutoffMinutes: idleSessionMinutes)
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

            var snapshot = UsageSnapshot(
                lastUpdated: now,
                rateLimits: rateLimits,
                rateLimitSource: rateLimitSource,
                standardLimits: standardLimits,
                rateLimitsFresh: rateLimitsFresh,
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
                topSessionHealths: topSessionHealths,
                provider: provider
            )
            snapshot.ledgerSince = ledgerSince

            return (snapshot, observedModels)
        }
    }

    // MARK: - Redundant aggregation skip

    private var cachedResult: AggregateResult?
    private var lastStatsCacheModDate: Date?
    private var lastRateLimits: RateLimitUsage?
    private var lastStandardLimits: StandardRateLimits?
    private var lastRateLimitSource: RateLimitSource?
    private var lastRateLimitsFresh = true
    private var lastIdleSessionMinutes: Int = -1
    private var lastAccountId: String?
    /// Which attribution the cached result was built under — part of the fingerprint so
    /// switching between `.all` and `.account(_)` always re-aggregates instead of serving
    /// a snapshot filtered (or not) for the wrong series.
    private var lastAttribution: Attribution = .all
    /// `now` quantised to `fingerprintTimeBucket`; part of the fingerprint so an idle
    /// provider (no FS events → no `invalidate()`) cannot serve a time-stale snapshot
    /// forever: the 5h-window tokens, today's counters and `lastUpdated` all depend on
    /// `now`, not only on the inputs.
    private var lastTimeBucket: Int = -1

    /// Width of the `now` bucket in the redundant-aggregation fingerprint (seconds).
    static let fingerprintTimeBucket: TimeInterval = 15 * 60

    /// Clear cached snapshot so the next aggregate() re-computes from scratch.
    /// Called by FileWatcher when JSONL or stats-cache files change.
    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        cachedResult = nil
    }

    func aggregate(
        rateLimits: RateLimitUsage?,
        rateLimitSource: RateLimitSource? = nil,
        standardLimits: StandardRateLimits? = nil,
        accountId: String? = nil,
        rateLimitsFresh: Bool = true,
        attribution: Attribution = .all,
        now: Date = Date()
    ) -> AggregateResult {
        // Idle session cutoff for context health (0 = never hide)
        let idleSessionMinutes = Int(UserDefaults.standard.double(forKey: UserDefaultsKeys.idleSessionMinutes))

        // Narrow lock scope: only guards cached-state reads/writes, not I/O.
        // Prevents blocking invalidate() callers on main actor during JSONL scans.
        let timeBucket = Int(now.timeIntervalSinceReferenceDate / Self.fingerprintTimeBucket)
        lock.lock()
        let statsCacheModDate = statsCacheReader?.lastModificationDate
        if let cached = cachedResult,
           timeBucket == lastTimeBucket,
           statsCacheModDate == lastStatsCacheModDate,
           rateLimits == lastRateLimits,
           standardLimits == lastStandardLimits,
           rateLimitSource == lastRateLimitSource,
           rateLimitsFresh == lastRateLimitsFresh,
           idleSessionMinutes == lastIdleSessionMinutes,
           accountId == lastAccountId,
           attribution == lastAttribution {
            lock.unlock()
            return cached
        }
        lock.unlock()

        // Expensive I/O runs without holding the lock.
        let statsCache = statsCacheReader?.read()
        let allEntries = sessionLogReader.readAllUsageEntries()

        // Side effects deferred to caller (RateLimitFetcher is @MainActor):
        // - activeUserModel = allEntries.last?.model
        // - setObservedModels(observedModels, accountId:)

        // One pass over allEntries builds the provider-wide accumulator; when attribution
        // is active, a second accumulator walks alongside it over the kept subsequence —
        // `now` is injectable via the function parameter (default = Date()) so tests pin
        // window-boundary behavior with a deterministic value.
        let (kept, unattributed) = attribution.partition(allEntries)
        let cachedDates = Set(statsCache?.dailyModelTokens.map(\.date) ?? [])
        var all = AggregationPass(provider: provider, now: now, cachedDates: cachedDates)
        var mine: AggregationPass? = attribution.isAttributed
            ? AggregationPass(provider: provider, now: now, cachedDates: cachedDates)
            : nil

        if mine != nil {
            // One walk, two accumulators: `kept` is a subsequence of `allEntries` in the
            // same ascending-timestamp order (see `Attribution.partition`), and message
            // ids are unique per entry (the readers dedupe on them), so a single cursor
            // over `kept` can be advanced in lock-step with the `allEntries` loop.
            var keptIndex = kept.startIndex
            for entry in allEntries {
                all.add(entry)
                if keptIndex < kept.endIndex, kept[keptIndex].messageId == entry.messageId {
                    mine?.add(entry)
                    keptIndex += 1
                }
            }
        } else {
            for entry in allEntries {
                all.add(entry)
            }
        }

        // Provider-wide pass's ledger key: unattributed, it's the plain account id (every
        // existing single-account user, unchanged); attributed, it's the dedicated
        // provider-wide series so the per-account series doesn't get polluted with totals
        // that include other accounts' turns.
        let providerKey: String? = accountId.map { id in
            attribution.isAttributed ? TokenLedger.providerWideCodexKey : TokenLedger.key(accountId: id, attribution: .all)
        }
        let (providerWide, observedAll) = all.finish(
            entries: allEntries, statsCache: statsCache, rateLimits: rateLimits,
            rateLimitSource: rateLimitSource, standardLimits: standardLimits,
            rateLimitsFresh: rateLimitsFresh, idleSessionMinutes: idleSessionMinutes,
            ledger: ledger, ledgerKey: providerKey
        )

        var detail = providerWide
        var observedModels = observedAll
        var activeModel = allEntries.last?.model
        if let mine {
            let detailKey = accountId.map { TokenLedger.key(accountId: $0, attribution: attribution) }
            let (d, o) = mine.finish(
                entries: kept, statsCache: statsCache, rateLimits: rateLimits,
                rateLimitSource: rateLimitSource, standardLimits: standardLimits,
                rateLimitsFresh: rateLimitsFresh, idleSessionMinutes: idleSessionMinutes,
                ledger: ledger, ledgerKey: detailKey
            )
            detail = d
            detail.unattributedTurnCount = unattributed
            observedModels = o
            activeModel = kept.last?.model
        }

        // Build side effects for @MainActor callers to apply
        let effects = SideEffects(
            activeUserModel: activeModel,
            observedModels: observedModels,
            accountId: accountId,
            provider: provider
        )

        let result = AggregateResult(detail: detail, providerWide: providerWide, effects: effects)

        // Cache the result and fingerprint (lock protects mutable state only)
        lock.lock()
        cachedResult = result
        lastStatsCacheModDate = statsCacheModDate
        lastRateLimits = rateLimits
        lastStandardLimits = standardLimits
        lastRateLimitSource = rateLimitSource
        lastRateLimitsFresh = rateLimitsFresh
        lastIdleSessionMinutes = idleSessionMinutes
        lastAccountId = accountId
        lastAttribution = attribution
        lastTimeBucket = timeBucket
        lock.unlock()

        return result
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

    private static func buildModelTokens(from map: TokenMap, provider: AIProvider) -> [ModelTokenSummary] {
        map.compactMap { modelId, tokens in
            guard isTrackedModel(modelId, provider: provider) else { return nil }
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
                estimatedCost: cost,
                reasoningTokens: tokens.reasoning
            )
        }.sorted { $0.totalTokens > $1.totalTokens }
    }
}
