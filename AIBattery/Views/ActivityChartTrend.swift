import SwiftUI

// MARK: - Trend data types

/// Change indicator for vs-yesterday / vs-last-week / vs-last-month comparisons.
struct ActivityChangeInfo {
    /// The direction itself, not a glyph: `TrendDirection` already owns both the arrow
    /// and its spoken form, and the view used to hard-code the arrows while
    /// `TrendDirection.accessibilityLabel` sat unused.
    let direction: TrendDirection
    let label: String
    let color: Color

    var symbol: String { direction.symbol }
    var accessibilityLabel: String { "\(direction.accessibilityLabel), \(label)" }
}

/// Precomputed trend data — avoids duplicate Date()/Calendar/throttleCount calls.
struct ActivityTrendData {
    let change: ActivityChangeInfo?
    let stat: String?
    let throttleCount: Int
    let peak: String?
    let throttleDays: Int
}

// MARK: - Trend computation (pure logic, no view code)

@MainActor
enum ActivityTrendComputation {
    static func compute(
        mode: ActivityChartMode,
        snapshot: UsageSnapshot,
        monthTotals: [String: Int]
    ) -> ActivityTrendData {
        let cal = Calendar.current
        let now = Date()

        switch mode {
        case .fiveHour:
            return ActivityTrendData(
                change: changeVsYesterday(snapshot, cal: cal, now: now),
                stat: "\(InsightsView.compactCount(snapshot.fiveHourTokens)) tokens in 5h",
                throttleCount: UsageViewModel.throttleCount(days: 1),
                peak: snapshot.peakHour.map { "Peak: \(InsightsView.formatHourLabel($0)):00" },
                throttleDays: 1
            )
        case .sevenDay:
            return ActivityTrendData(
                change: changeVsLastWeek(snapshot, cal: cal, now: now),
                stat: snapshot.sevenDayTokens > 0 ? "\(InsightsView.compactCount(snapshot.sevenDayTokens)) tokens in 7d" : nil,
                throttleCount: UsageViewModel.throttleCount(days: 7),
                peak: snapshot.busiestDayOfWeek.map { "Peak: \($0.name)s" },
                throttleDays: 7
            )
        case .monthly:
            let nowComps = cal.dateComponents([.year, .month], from: now)
            let thisMonthKey = nowComps.year.flatMap { y in nowComps.month.map { m in String(format: "%04d-%02d", y, m) } }
            let lastMonthKey: String? = cal.date(byAdding: .month, value: -1, to: now).flatMap { d in
                let c = cal.dateComponents([.year, .month], from: d)
                return c.year.flatMap { y in c.month.map { m in String(format: "%04d-%02d", y, m) } }
            }
            let thisMonth = thisMonthKey.flatMap { monthTotals[$0] } ?? 0
            let lastMonth = lastMonthKey.flatMap { monthTotals[$0] } ?? 0
            // Window both to the same twelve months the chart above plots. Reducing all
            // of `monthTotals` folds every month the aggregator ever wrote, so "N in 12m"
            // and "Peak" disagreed with the chart for anyone keeping more than a year of
            // logs (Claude Code's 30-day default hides it; raising `cleanupPeriodDays`
            // or hoarding Codex rollouts does not).
            let windowKeys = ActivityChartData.rollingTwelveMonthKeys(now: now)
            let windowed = windowKeys.compactMap { key in monthTotals[key].map { (key, $0) } }
            let twelveMonthTotal = windowed.reduce(0) { $0 + $1.1 }
            let busiestLabel: String? = {
                guard let peak = windowed.max(by: { $0.1 < $1.1 }), peak.1 > 0,
                      let date = DateFormatters.dateKey.date(from: peak.0 + "-01") else { return nil }
                return InsightsView.monthAbbrev(date)
            }()
            return ActivityTrendData(
                change: monthChangeInfo(thisMonth: thisMonth, lastMonth: lastMonth, cal: cal, now: now),
                stat: twelveMonthTotal > 0 ? "\(InsightsView.compactCount(twelveMonthTotal)) in 12m" : nil,
                throttleCount: UsageViewModel.throttleCount(days: 30),
                peak: busiestLabel.map { "Peak: \($0)" },
                throttleDays: 30
            )
        }
    }

    static func copyText(_ data: ActivityTrendData) -> String {
        var lines: [String] = []
        if let change = data.change {
            lines.append("\(change.symbol) \(change.label)")
        }
        if let stat = data.stat {
            lines.append(stat)
        }
        lines.append("Throttled: \(data.throttleCount > 0 ? "\(data.throttleCount)×" : "0")")
        if let peak = data.peak {
            lines.append(peak)
        }
        return lines.joined(separator: " · ")
    }

    // MARK: - Comparison helpers

    static func changeVsYesterday(_ snapshot: UsageSnapshot, cal: Calendar = .current, now: Date = .init()) -> ActivityChangeInfo? {
        let todayStr = DateFormatters.dateKey.string(from: now)
        let yesterdayStr = DateFormatters.dateKey.string(
            from: cal.date(byAdding: .day, value: -1, to: now) ?? now
        )

        let todayTokens = snapshot.dailyTokenTotals[todayStr] ?? 0
        guard let yesterdayTokens = snapshot.dailyTokenTotals[yesterdayStr] else { return nil }
        return percentChangeInfo(current: todayTokens, previous: yesterdayTokens, suffix: "vs yesterday")
    }

    static func changeVsLastWeek(_ snapshot: UsageSnapshot, cal: Calendar = .current, now: Date = .init()) -> ActivityChangeInfo? {
        let today = cal.startOfDay(for: now)
        let weekday = cal.component(.weekday, from: today)
        let daysSinceMonday = (weekday + 5) % 7
        guard let thisWeekStart = cal.date(byAdding: .day, value: -daysSinceMonday, to: today),
              let lastWeekStart = cal.date(byAdding: .day, value: -7, to: thisWeekStart),
              let lastWeekSameDay = cal.date(byAdding: .day, value: daysSinceMonday, to: lastWeekStart) else {
            return nil
        }

        let thisWeekRange = DateFormatters.dateKey.string(from: thisWeekStart)...DateFormatters.dateKey.string(from: today)
        let lastWeekRange = DateFormatters.dateKey.string(from: lastWeekStart)...DateFormatters.dateKey.string(from: lastWeekSameDay)

        // Single pass: accumulate both week token totals simultaneously
        var thisWeekTotal = 0
        var lastWeekTotal = 0
        for (date, tokens) in snapshot.dailyTokenTotals {
            if thisWeekRange.contains(date) {
                thisWeekTotal += tokens
            } else if lastWeekRange.contains(date) {
                lastWeekTotal += tokens
            }
        }

        return percentChangeInfo(current: thisWeekTotal, previous: lastWeekTotal, suffix: "vs last week")
    }

    static func monthChangeInfo(thisMonth: Int, lastMonth: Int, cal: Calendar = .current, now: Date = .init()) -> ActivityChangeInfo? {
        let dayOfMonth = cal.component(.day, from: now)
        guard dayOfMonth >= 4,
              let daysInMonth = cal.range(of: .day, in: .month, for: now)?.count else { return nil }
        let projected = thisMonth * daysInMonth / dayOfMonth
        return percentChangeInfo(current: projected, previous: lastMonth, suffix: "vs last month")
    }

    // MARK: - Shared formatting

    private static func changeInfo(diff: Int, suffix: String) -> ActivityChangeInfo {
        if diff > 0 {
            ActivityChangeInfo(direction: .up, label: "+\(diff) \(suffix)", color: ThemeColors.trendColor(.up))
        } else if diff < 0 {
            ActivityChangeInfo(direction: .down, label: "\(diff) \(suffix)", color: ThemeColors.trendColor(.down))
        } else {
            ActivityChangeInfo(direction: .flat, label: "same as \(suffix.replacingOccurrences(of: "vs ", with: ""))", color: ThemeColors.secondaryLabel)
        }
    }

    /// Absolute floor for the `previous` period: below this there is nothing to compare
    /// against at all.
    private static let meaningfulPreviousFloor = 1_000

    /// ...and `previous` must also be at least this share of `current`. A fixed token
    /// floor is calibrated to one machine: 1 000 tokens is 0.003% of a normal day here,
    /// so a single stray hook session cleared it and the row read ">999% vs yesterday"
    /// — exactly the noise the floor exists to suppress. Making it relative keeps the
    /// threshold meaningful whatever a user's daily volume is.
    private static let meaningfulPreviousShare = 0.05

    /// The `previous` value below which a comparison is noise rather than a trend.
    static func meaningfulPreviousThreshold(current: Int) -> Int {
        max(meaningfulPreviousFloor, Int(Double(current) * meaningfulPreviousShare))
    }

    /// Cap the displayed positive percentage. Above the cap, the label shows
    /// `>999%` so the spike is still visible without rendering a number that's
    /// mathematically true but visually broken (5-digit percentages overflow the
    /// trend row's layout and read as noise).
    private static let maxDisplayedPercent = 999

    private static func percentChangeInfo(current: Int, previous: Int, suffix: String) -> ActivityChangeInfo? {
        // Suppress trend when previous is missing or below the meaningful threshold.
        // The user reads the absolute numbers from the chart; a noisy multi-thousand-
        // percent comparison helps nobody.
        guard previous >= meaningfulPreviousThreshold(current: current) else { return nil }

        let diff = current - previous
        let pct = Int(round(Double(diff) / Double(previous) * 100))
        if pct > 10 {
            let label = pct > maxDisplayedPercent
                ? ">\(maxDisplayedPercent)% \(suffix)"
                : "+\(pct)% \(suffix)"
            return ActivityChangeInfo(direction: .up, label: label, color: ThemeColors.trendColor(.up))
        } else if pct < -10 {
            return ActivityChangeInfo(direction: .down, label: "\(pct)% \(suffix)", color: ThemeColors.trendColor(.down))
        } else {
            return ActivityChangeInfo(direction: .flat, label: "~same as \(suffix.replacingOccurrences(of: "vs ", with: ""))", color: ThemeColors.secondaryLabel)
        }
    }
}
