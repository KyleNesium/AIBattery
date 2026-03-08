import Foundation

/// Pure data transformations for activity charts — extracted from ActivityChartView for testability.
enum ActivityChartData {

    struct DailyPoint {
        let key: String
        let date: Date
        let count: Int
    }

    struct HourlyPoint {
        let offset: Int
        let hour: Int
        let count: Int
    }

    struct MonthlyPoint {
        let key: String
        let date: Date
        let count: Int
    }

    // MARK: - Daily (7D)

    /// Generates 7 daily data points (6 days ago through today), filling gaps with zero.
    static func dailyData(from activity: [DailyActivity], now: Date = .now) -> [DailyPoint] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)

        var lookup: [String: Int] = [:]
        for day in activity {
            lookup[day.date] = day.messageCount
        }

        return (0..<7).compactMap { offset in
            guard let date = cal.date(byAdding: .day, value: -(6 - offset), to: today) else { return nil }
            let key = DateFormatters.dateKey.string(from: date)
            return DailyPoint(key: key, date: date, count: lookup[key] ?? 0)
        }
    }

    // MARK: - Hourly (12H)

    /// Generates 12 hourly data points for the trailing 12-hour window.
    static func hourlyData(from hourCounts: [String: Int], now: Date = .now) -> [HourlyPoint] {
        let currentHour = Calendar.current.component(.hour, from: now)
        return (0..<12).map { offset in
            let hour = (currentHour - 11 + offset + 24) % 24
            return HourlyPoint(offset: offset, hour: hour, count: hourCounts[String(hour)] ?? 0)
        }
    }

    // MARK: - Monthly (12M)

    /// Single-pass aggregation of daily activity into month-keyed totals (e.g. "2026-03" → 142).
    static func monthTotals(from activity: [DailyActivity]) -> [String: Int] {
        let cal = Calendar.current
        var result: [String: Int] = [:]
        for day in activity {
            guard let date = day.parsedDate else { continue }
            let comps = cal.dateComponents([.year, .month], from: date)
            guard let y = comps.year, let m = comps.month else { continue }
            let key = String(format: "%04d-%02d", y, m)
            result[key, default: 0] += day.messageCount
        }
        return result
    }

    /// Generates 12 monthly data points with current-month projection.
    static func monthlyData(from activity: [DailyActivity], now: Date = .now) -> [MonthlyPoint] {
        let cal = Calendar.current
        let lookup = monthTotals(from: activity)

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
