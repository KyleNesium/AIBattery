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
}
