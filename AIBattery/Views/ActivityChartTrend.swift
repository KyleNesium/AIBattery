import SwiftUI

// MARK: - Trend data types

/// Change indicator for vs-yesterday / vs-last-week / vs-last-month comparisons.
struct ActivityChangeInfo {
    let symbol: String
    let label: String
    let color: Color
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
            let busiestLabel: String? = {
                guard let peak = monthTotals.max(by: { $0.value < $1.value }),
                      let date = DateFormatters.dateKey.date(from: peak.key + "-01") else { return nil }
                return InsightsView.monthAbbrev(date)
            }()
            return ActivityTrendData(
                change: monthChangeInfo(thisMonth: thisMonth, lastMonth: lastMonth, cal: cal, now: now),
                stat: thisMonth > 0 ? "\(InsightsView.compactCount(thisMonth)) this month" : nil,
                throttleCount: UsageViewModel.throttleCount(days: 30),
                peak: busiestLabel.map { "Peak: \($0)" },
                throttleDays: 30
            )
        }
    }

    static func copyText(_ data: ActivityTrendData) -> String {
        var lines: [String] = []
        if let change = data.change { lines.append("\(change.symbol) \(change.label)") }
        if let stat = data.stat { lines.append(stat) }
        lines.append("Throttled: \(data.throttleCount > 0 ? "\(data.throttleCount)×" : "0")")
        if let peak = data.peak { lines.append(peak) }
        return lines.joined(separator: " · ")
    }

    // MARK: - Comparison helpers

    static func changeVsYesterday(_ snapshot: UsageSnapshot, cal: Calendar = .current, now: Date = .init()) -> ActivityChangeInfo? {
        let yesterdayStr = DateFormatters.dateKey.string(
            from: cal.date(byAdding: .day, value: -1, to: now) ?? now
        )

        guard let yesterday = snapshot.dailyActivity.first(where: { $0.date == yesterdayStr }) else {
            return nil
        }

        let diff = snapshot.todayMessages - yesterday.messageCount
        return changeInfo(diff: diff, suffix: "vs yesterday")
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

        // Single pass: accumulate both week totals simultaneously
        var thisWeekTotal = 0
        var lastWeekTotal = 0
        for day in snapshot.dailyActivity {
            if thisWeekRange.contains(day.date) {
                thisWeekTotal += day.messageCount
            } else if lastWeekRange.contains(day.date) {
                lastWeekTotal += day.messageCount
            }
        }

        guard lastWeekTotal > 0 else { return nil }
        return percentChangeInfo(current: thisWeekTotal, previous: lastWeekTotal, suffix: "vs last week")
    }

    static func monthChangeInfo(thisMonth: Int, lastMonth: Int, cal: Calendar = .current, now: Date = .init()) -> ActivityChangeInfo? {
        guard lastMonth > 0 else { return nil }

        let dayOfMonth = cal.component(.day, from: now)
        guard dayOfMonth >= 4,
              let daysInMonth = cal.range(of: .day, in: .month, for: now)?.count else { return nil }
        let projected = thisMonth * daysInMonth / dayOfMonth
        return percentChangeInfo(current: projected, previous: lastMonth, suffix: "vs last month")
    }

    // MARK: - Shared formatting

    private static func changeInfo(diff: Int, suffix: String) -> ActivityChangeInfo {
        if diff > 0 {
            return ActivityChangeInfo(symbol: "↑", label: "+\(diff) \(suffix)", color: ThemeColors.trendColor(.up))
        } else if diff < 0 {
            return ActivityChangeInfo(symbol: "↓", label: "\(diff) \(suffix)", color: ThemeColors.trendColor(.down))
        } else {
            return ActivityChangeInfo(symbol: "→", label: "same as \(suffix.replacingOccurrences(of: "vs ", with: ""))", color: ThemeColors.secondaryLabel)
        }
    }

    private static func percentChangeInfo(current: Int, previous: Int, suffix: String) -> ActivityChangeInfo {
        let diff = current - previous
        let pct = Int(round(Double(diff) / Double(previous) * 100))
        if pct > 10 {
            return ActivityChangeInfo(symbol: "↑", label: "+\(pct)% \(suffix)", color: ThemeColors.trendColor(.up))
        } else if pct < -10 {
            return ActivityChangeInfo(symbol: "↓", label: "\(pct)% \(suffix)", color: ThemeColors.trendColor(.down))
        } else {
            return ActivityChangeInfo(symbol: "→", label: "~same as \(suffix.replacingOccurrences(of: "vs ", with: ""))", color: ThemeColors.secondaryLabel)
        }
    }
}
