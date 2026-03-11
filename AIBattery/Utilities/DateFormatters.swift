import Foundation

/// Centralized date formatters — single source of truth.
/// DateFormatter is expensive to create; these are allocated once and reused.
enum DateFormatters {
    /// "yyyy-MM-dd" — date keys for daily activity, stats cache lookups.
    static let dateKey: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// ISO 8601 with fractional seconds — JSONL timestamps, firstSessionDate.
    static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// "EEE" — short day names (Mon, Tue, ...).
    static let shortDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE"
        return f
    }()

    /// "MMM" — short month names (Jan, Feb, ...).
    static let shortMonth: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM"
        return f
    }()

    /// "Nov 6" — month + day, no year. Pinned to en_US_POSIX for deterministic output.
    static let rangeShort: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"
        return f
    }()

    /// "Nov 6, 2025" — month + day + year. Pinned to en_US_POSIX for deterministic output.
    static let rangeWithYear: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    /// Formats a date range: same year → "Nov 6 – Mar 10, 2026", cross-year → "Dec 15, 2025 – Mar 10, 2026".
    static func formatDateRange(from start: Date, to end: Date) -> String {
        let cal = Calendar.current
        let sameYear = cal.component(.year, from: start) == cal.component(.year, from: end)
        if sameYear {
            return "\(rangeShort.string(from: start)) – \(rangeWithYear.string(from: end))"
        }
        return "\(rangeWithYear.string(from: start)) – \(rangeWithYear.string(from: end))"
    }
}
