import Foundation

/// Pure data transformations for activity charts — extracted from InsightsView for testability.
/// All chart modes show token counts (input+output) rather than message counts.
enum ActivityChartData {

    struct DailyPoint: Identifiable {
        var id: String { key }
        let key: String
        let date: Date
        let count: Int
    }

    struct FiveHourPoint: Identifiable {
        var id: Int { offset }
        let offset: Int  // 0 = oldest (5h ago), 19 = most recent
        let count: Int   // tokens in this 15-minute bucket
    }

    struct MonthlyPoint: Identifiable {
        var id: String { key }
        let key: String
        let date: Date
        let count: Int
    }

    // MARK: - 5-Hour (20 × 15-minute buckets)

    /// Generates 20 five-hour data points from pre-bucketed token data.
    /// Bucket 0 = oldest (5h ago), bucket 19 = most recent 15 minutes.
    static func fiveHourData(from buckets: [Int: Int]) -> [FiveHourPoint] {
        (0..<20).map { offset in
            FiveHourPoint(offset: offset, count: buckets[offset] ?? 0)
        }
    }

    // MARK: - 7-Day (daily token totals)

    /// Generates 7 daily data points (6 days ago through today), filling gaps with zero.
    /// Uses token totals per date instead of message counts.
    static func sevenDayData(from dailyTokens: [String: Int], now: Date = .now) -> [DailyPoint] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)

        return (0..<7).compactMap { offset in
            guard let date = cal.date(byAdding: .day, value: -(6 - offset), to: today) else { return nil }
            let key = DateFormatters.dateKey.string(from: date)
            return DailyPoint(key: key, date: date, count: dailyTokens[key] ?? 0)
        }
    }

    // MARK: - Monthly (12M token totals)

    /// Single-pass aggregation of daily token totals into month-keyed totals.
    static func monthTokenTotals(from dailyTokens: [String: Int]) -> [String: Int] {
        var result: [String: Int] = [:]
        for (dateKey, tokens) in dailyTokens {
            // dateKey must be "yyyy-MM-dd" format — skip malformed keys
            guard dateKey.count >= 7,
                  dateKey[dateKey.index(dateKey.startIndex, offsetBy: 4)] == "-"
            else { continue }
            let monthKey = String(dateKey.prefix(7))
            result[monthKey, default: 0] += tokens
        }
        return result
    }

    /// Generates 12 monthly data points with current-month projection.
    /// Accepts pre-computed month totals.
    static func monthlyData(from lookup: [String: Int], now: Date = .now) -> [MonthlyPoint] {
        let cal = Calendar.current

        let nowComps = cal.dateComponents([.year, .month], from: now)
        guard let thisMonth = cal.date(from: nowComps) else { return [] }
        guard let nowYear = nowComps.year, let nowMonth = nowComps.month else { return [] }
        let thisMonthKey = String(format: "%04d-%02d", nowYear, nowMonth)

        return (0..<12).compactMap { offset in
            guard let date = cal.date(byAdding: .month, value: -(11 - offset), to: thisMonth) else { return nil }
            let comps = cal.dateComponents([.year, .month], from: date)
            guard let y = comps.year, let m = comps.month else { return nil }
            let key = String(format: "%04d-%02d", y, m)
            let total = lookup[key] ?? 0

            // Project current month to full-month pace so it's comparable.
            // Skip projection in the first 3 days — too few data points to extrapolate.
            let count: Int
            if key == thisMonthKey, total > 0,
               let daysInMonth = cal.range(of: .day, in: .month, for: now)?.count {
                let dayOfMonth = cal.component(.day, from: now)
                count = dayOfMonth >= 4 ? total * daysInMonth / dayOfMonth : total
            } else {
                count = total
            }

            return MonthlyPoint(key: key, date: date, count: count)
        }
    }
}
