import Foundation
import os

final class UsageAggregator {
    private let statsCacheReader = StatsCacheReader.shared
    private let sessionLogReader = SessionLogReader.shared

    // Cache for ~/.claude.json — only re-read when file mod date changes.
    private var cachedAccountInfo: AccountInfo?
    private var accountInfoModDate: Date?

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

    func aggregate(rateLimits: RateLimitUsage?, orgName: String? = nil) -> UsageSnapshot {
        let statsCache = statsCacheReader.read()
        let accountInfo = readAccountInfo()

        // Single JSONL scan — entries are already cached by SessionLogReader.
        let allEntries = sessionLogReader.readAllUsageEntries()

        // Token window: 0 = all time, 1–7 = that many days
        let tokenWindowDays = Int(UserDefaults.standard.double(forKey: UserDefaultsKeys.tokenWindowDays))

        // Single-pass filter: extract today's entries and windowed entries simultaneously.
        // Since allEntries is sorted by timestamp, we can iterate once and bucket efficiently.
        let today = Calendar.current.startOfDay(for: Date())
        let windowStart: Date? = tokenWindowDays > 0
            ? Calendar.current.date(byAdding: .day, value: -tokenWindowDays, to: Date())
            : nil

        var todayEntries: [AssistantUsageEntry] = []
        var windowedMap: [String: (input: Int, output: Int, cacheRead: Int, cacheWrite: Int)] = [:]

        for entry in allEntries {
            if entry.timestamp >= today {
                todayEntries.append(entry)
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

        let todayDate = Self.dateFormatter.string(from: Date())
        let todayMessages = todayEntries.count
        let todaySessions = Set(todayEntries.map(\.sessionId)).count
        let todayToolCalls = statsCache?.dailyActivity
            .first(where: { $0.date == todayDate })?.toolCallCount ?? 0

        // Dates already covered by stats cache
        let cachedDates = Set(statsCache?.dailyModelTokens.map(\.date) ?? [])

        // Only show models active in the last 72 hours to reduce noise.
        // Build set of recently-active model IDs from dailyModelTokens + today's JSONL.
        let cutoffDate = Calendar.current.date(byAdding: .hour, value: -72, to: Date()) ?? Date()
        let cutoffDateStr = Self.dateFormatter.string(from: cutoffDate)
        var recentModelIds = Set<String>()
        if let cache = statsCache {
            for entry in cache.dailyModelTokens where entry.date >= cutoffDateStr {
                for (modelId, tokens) in entry.tokensByModel where tokens > 0 {
                    recentModelIds.insert(modelId)
                }
            }
        }
        for entry in todayEntries {
            recentModelIds.insert(entry.model)
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

            let uncachedEntries = todayEntries.filter { entry in
                let entryDate = Self.dateFormatter.string(from: entry.timestamp)
                return !cachedDates.contains(entryDate)
            }
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

        // Token health assessment — reuse allEntries for multi-session support
        let tokenHealth = TokenHealthMonitor.shared.assessCurrentSession(entries: allEntries)
        let topSessionHealths = TokenHealthMonitor.shared.topSessions(entries: allEntries, limit: 5)

        // Org name priority: API header → ~/.claude.json → UserDefaults (user-set)
        let displayName = accountInfo?.displayName
            ?? UserDefaults.standard.string(forKey: UserDefaultsKeys.displayName)
        let resolvedOrgName = orgName
            ?? accountInfo?.organizationName
            ?? UserDefaults.standard.string(forKey: UserDefaultsKeys.orgName)
        let billing = accountInfo?.billingType

        // Persist API-sourced org name to UserDefaults — only if user hasn't manually set one
        let userSetOrg = UserDefaults.standard.string(forKey: UserDefaultsKeys.orgName) ?? ""
        if let name = orgName, !name.isEmpty, userSetOrg.isEmpty {
            UserDefaults.standard.set(name, forKey: UserDefaultsKeys.orgName)
        }

        return UsageSnapshot(
            lastUpdated: Date(),
            rateLimits: rateLimits,
            displayName: displayName,
            organizationName: resolvedOrgName,
            billingType: billing,
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
            dailyActivity: statsCache?.dailyActivity ?? [],
            hourCounts: statsCache?.hourCounts ?? [:],
            tokenHealth: tokenHealth,
            topSessionHealths: topSessionHealths
        )
    }

    private func readAccountInfo() -> AccountInfo? {
        let path = ClaudePaths.accountConfigPath

        // Check mod date — skip re-read if unchanged
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let modDate = attrs[.modificationDate] as? Date {
            if modDate == accountInfoModDate, let cached = cachedAccountInfo {
                return cached
            }
            accountInfoModDate = modDate
        }

        let url = ClaudePaths.accountConfig
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            // File missing is normal for first-run; other errors are worth logging.
            if (error as NSError).code != NSFileReadNoSuchFileError {
                AppLogger.files.warning("Failed to read ~/.claude.json: \(error.localizedDescription, privacy: .public)")
            }
            return nil
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            AppLogger.files.warning("~/.claude.json is not valid JSON")
            return nil
        }
        guard let oauth = json["oauthAccount"] as? [String: Any] else { return nil }
        let info = AccountInfo(
            displayName: oauth["displayName"] as? String,
            organizationName: oauth["organizationName"] as? String,
            billingType: oauth["organizationBillingType"] as? String
        )
        cachedAccountInfo = info
        return info
    }
}

private struct AccountInfo {
    let displayName: String?
    let organizationName: String?
    let billingType: String?
}
