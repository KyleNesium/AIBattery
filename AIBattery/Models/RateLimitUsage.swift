import Foundation

/// Parsed from Anthropic's unified rate limit headers.
///
/// The API uses a unified sliding-window system with two windows:
///   - 5-hour window (short-term burst)
///   - 7-day window (long-term usage)
/// Each reports a utilization fraction (0.0–1.0) and a reset timestamp.
/// The `representative-claim` tells which window is the binding constraint.
struct RateLimitUsage: Equatable, Codable {
    /// Window identifiers used in API headers.
    static let fiveHourWindow = "five_hour"
    static let sevenDayWindow = "seven_day"

    /// Window durations — used to derive how far into a window the current reading is.
    static let fiveHourWindowDuration: TimeInterval = 5 * 3_600
    static let sevenDayWindowDuration: TimeInterval = 7 * 24 * 3_600

    /// Rollover-artifact guard thresholds. A window reading at/above
    /// `rolloverArtifactUtilizationThreshold` whose reset implies the window started
    /// less than `rolloverArtifactGracePeriod` ago is treated as a stale carry-over
    /// from the *previous* window (server-side rollover lag), not a genuine limit-hit —
    /// you cannot consume ~all of a multi-hour quota in the first few minutes.
    static let rolloverArtifactUtilizationThreshold = 0.95
    static let rolloverArtifactGracePeriod: TimeInterval = 600 // 10 minutes

    private static func inferredWindowStatus(
        explicitStatus: String?,
        overallStatus: String,
        representativeClaim: String,
        window: String
    ) -> String {
        if let explicitStatus {
            return explicitStatus
        }
        guard overallStatus == "throttled" else { return overallStatus }
        return representativeClaim == window ? "throttled" : "allowed"
    }

    /// The binding constraint: "five_hour" or "seven_day"
    let representativeClaim: String

    /// 5-hour window
    let fiveHourUtilization: Double // 0.0 – 1.0
    let fiveHourReset: Date?
    let fiveHourStatus: String // "allowed" or "throttled"

    /// 7-day window
    let sevenDayUtilization: Double
    let sevenDayReset: Date?
    let sevenDayStatus: String

    /// Overall status
    let overallStatus: String // "allowed" or "throttled"

    /// Which provider produced this reading. Decodes as `.claude` for pre-v2.7
    /// persisted snapshots. Drives window labels only — thresholds and guards
    /// are provider-neutral.
    let provider: AIProvider

    /// Actual window durations from the provider payload (Codex sends them;
    /// Anthropic doesn't — nil means "assume 300 / 10080").
    let fiveHourWindowMinutes: Int?
    let sevenDayWindowMinutes: Int?

    init(
        representativeClaim: String,
        fiveHourUtilization: Double, fiveHourReset: Date?, fiveHourStatus: String,
        sevenDayUtilization: Double, sevenDayReset: Date?, sevenDayStatus: String,
        overallStatus: String,
        provider: AIProvider = .claude,
        fiveHourWindowMinutes: Int? = nil,
        sevenDayWindowMinutes: Int? = nil
    ) {
        self.representativeClaim = representativeClaim
        self.fiveHourUtilization = fiveHourUtilization
        self.fiveHourReset = fiveHourReset
        self.fiveHourStatus = fiveHourStatus
        self.sevenDayUtilization = sevenDayUtilization
        self.sevenDayReset = sevenDayReset
        self.sevenDayStatus = sevenDayStatus
        self.overallStatus = overallStatus
        self.provider = provider
        self.fiveHourWindowMinutes = fiveHourWindowMinutes
        self.sevenDayWindowMinutes = sevenDayWindowMinutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        representativeClaim = try c.decode(String.self, forKey: .representativeClaim)
        fiveHourUtilization = try c.decode(Double.self, forKey: .fiveHourUtilization)
        fiveHourReset = try c.decodeIfPresent(Date.self, forKey: .fiveHourReset)
        fiveHourStatus = try c.decode(String.self, forKey: .fiveHourStatus)
        sevenDayUtilization = try c.decode(Double.self, forKey: .sevenDayUtilization)
        sevenDayReset = try c.decodeIfPresent(Date.self, forKey: .sevenDayReset)
        sevenDayStatus = try c.decode(String.self, forKey: .sevenDayStatus)
        overallStatus = try c.decode(String.self, forKey: .overallStatus)
        provider = try c.decodeIfPresent(AIProvider.self, forKey: .provider) ?? .claude
        fiveHourWindowMinutes = try c.decodeIfPresent(Int.self, forKey: .fiveHourWindowMinutes)
        sevenDayWindowMinutes = try c.decodeIfPresent(Int.self, forKey: .sevenDayWindowMinutes)
    }

    // MARK: - Convenience

    /// Resolve a per-window value by the binding window (`representativeClaim`):
    /// the 7-day value when it is the binding constraint, the 5-hour value
    /// otherwise (matching the original switches' `default:` arm). Single home
    /// for the dispatch that was previously copy-pasted across six properties.
    private func bindingValue<T>(fiveHour: T, sevenDay: T) -> T {
        representativeClaim == Self.sevenDayWindow ? sevenDay : fiveHour
    }

    /// The utilization percentage of the binding window (0–100).
    var requestsPercentUsed: Double {
        bindingValue(fiveHour: fiveHourUtilization, sevenDay: sevenDayUtilization) * 100.0
    }

    /// 5-hour utilization as percentage (0–100).
    var fiveHourPercent: Double { fiveHourUtilization * 100.0 }

    /// 7-day utilization as percentage (0–100).
    var sevenDayPercent: Double { sevenDayUtilization * 100.0 }

    /// Reset date of the binding window.
    var bindingReset: Date? {
        bindingValue(fiveHour: fiveHourReset, sevenDay: sevenDayReset)
    }

    /// "7-Day" for Claude, "Weekly" for Codex — same 7-day window, provider vocabulary.
    var sevenDayDisplayLabel: String { provider.secondaryWindowLabel }

    /// Human-readable label for the binding window.
    var bindingWindowLabel: String {
        bindingValue(fiveHour: "5-hour", sevenDay: provider == .codex ? "Weekly" : "7-day")
    }

    /// Compact code for the binding window, for the menu bar: "5H" or "7D".
    /// Lets a throttled countdown say which window you're waiting on (hours vs a day+).
    var bindingWindowShortCode: String {
        bindingValue(fiveHour: "5H", sevenDay: provider.secondaryWindowShortCode)
    }

    /// Whether the user is currently throttled.
    /// Checks overall status and per-window statuses — the API may report
    /// a window as "throttled" before the overall status reflects it.
    var isThrottled: Bool {
        overallStatus == "throttled"
            || fiveHourStatus == "throttled"
            || sevenDayStatus == "throttled"
    }

    /// Whether a specific window is currently throttled.
    /// A global throttled status alone is not enough to mark every window as throttled.
    func isWindowThrottled(_ window: String) -> Bool {
        switch window {
        case Self.sevenDayWindow:
            sevenDayStatus == "throttled"
        default:
            fiveHourStatus == "throttled"
        }
    }

    /// Force a throttled state when the HTTP response proves the account is rate limited
    /// but the unified headers lag behind and still report an allowed status/utilization.
    func markedThrottled(bindingWindow: String? = nil) -> RateLimitUsage {
        let window = bindingWindow ?? representativeClaim
        return RateLimitUsage(
            representativeClaim: representativeClaim,
            fiveHourUtilization: fiveHourUtilization,
            fiveHourReset: fiveHourReset,
            fiveHourStatus: window == Self.fiveHourWindow ? "throttled" : fiveHourStatus,
            sevenDayUtilization: sevenDayUtilization,
            sevenDayReset: sevenDayReset,
            sevenDayStatus: window == Self.sevenDayWindow ? "throttled" : sevenDayStatus,
            overallStatus: "throttled",
            provider: provider,
            fiveHourWindowMinutes: fiveHourWindowMinutes,
            sevenDayWindowMinutes: sevenDayWindowMinutes
        )
    }

    /// Return a copy normalizing two kinds of stale state. Used on the cache /
    /// stale-fallback paths (cache restore, runtime cache hit, snapshot stale
    /// fallback) — never on fresh data.
    ///
    /// 1. **Expired window** (reset in the past): utilization → 0, reset → nil,
    ///    status → "allowed". The window has rolled over; showing the old value
    ///    would mislead until the first fresh fetch lands.
    /// 2. **Unbounded throttle** (status "throttled" with *no* reset): a genuine
    ///    quota throttle always carries a reset, so a reset-less throttle can never
    ///    be aged out by (1) and would stick forever on the stale path. Drop the
    ///    throttle flag (status → "allowed") while keeping the last-known
    ///    utilization, so the bar stops claiming "Throttled" but still reflects
    ///    how full the window was. A fresh fetch re-establishes the truth.
    func withClearedExpiredWindows(now: Date = .now) -> RateLimitUsage {
        let fiveHourExpired = (fiveHourReset.map { $0 <= now } ?? false)
        let sevenDayExpired = (sevenDayReset.map { $0 <= now } ?? false)
        let fiveHourUnboundedThrottle = (fiveHourReset == nil && fiveHourStatus == "throttled")
        let sevenDayUnboundedThrottle = (sevenDayReset == nil && sevenDayStatus == "throttled")

        guard fiveHourExpired || sevenDayExpired
            || fiveHourUnboundedThrottle || sevenDayUnboundedThrottle else { return self }

        let bindingCleared = bindingValue(
            fiveHour: fiveHourExpired || fiveHourUnboundedThrottle,
            sevenDay: sevenDayExpired || sevenDayUnboundedThrottle
        )

        return RateLimitUsage(
            representativeClaim: representativeClaim,
            fiveHourUtilization: fiveHourExpired ? 0 : fiveHourUtilization,
            fiveHourReset: fiveHourExpired ? nil : fiveHourReset,
            fiveHourStatus: (fiveHourExpired || fiveHourUnboundedThrottle) ? "allowed" : fiveHourStatus,
            sevenDayUtilization: sevenDayExpired ? 0 : sevenDayUtilization,
            sevenDayReset: sevenDayExpired ? nil : sevenDayReset,
            sevenDayStatus: (sevenDayExpired || sevenDayUnboundedThrottle) ? "allowed" : sevenDayStatus,
            overallStatus: bindingCleared ? "allowed" : overallStatus,
            provider: provider,
            fiveHourWindowMinutes: fiveHourWindowMinutes,
            sevenDayWindowMinutes: sevenDayWindowMinutes
        )
    }

    /// Whether a window reading is a rollover artifact: near-full utilization on a
    /// window whose reset says it only just started. Such a reading is the previous
    /// window's usage lingering on a fresh window (server-side eventual consistency at
    /// the reset boundary) and must not be shown as "Limit reached".
    private static func isRolloverArtifact(
        utilization: Double,
        reset: Date?,
        windowDuration: TimeInterval,
        now: Date
    ) -> Bool {
        guard utilization >= rolloverArtifactUtilizationThreshold, let reset else { return false }
        let timeUntilReset = reset.timeIntervalSince(now)
        // A past/at reset is the expired-window case (handled by withClearedExpiredWindows).
        guard timeUntilReset > 0 else { return false }
        let elapsed = windowDuration - timeUntilReset
        return elapsed < rolloverArtifactGracePeriod
    }

    /// Return a copy that suppresses rollover artifacts — near-full utilization on a
    /// window that just rolled over. Unlike `withClearedExpiredWindows`, the reset is
    /// the *valid* new-window reset, so it's preserved (the countdown keeps running);
    /// only the stale utilization/status is cleared. Used on the displayed rate-limit
    /// data so a window that reset moments ago doesn't read "100% / Limit reached"
    /// until the next poll catches up.
    func withClearedRolloverArtifacts(now: Date = .now) -> RateLimitUsage {
        let fiveHourArtifact = Self.isRolloverArtifact(
            utilization: fiveHourUtilization, reset: fiveHourReset,
            windowDuration: Self.fiveHourWindowDuration, now: now
        )
        let sevenDayArtifact = Self.isRolloverArtifact(
            utilization: sevenDayUtilization, reset: sevenDayReset,
            windowDuration: Self.sevenDayWindowDuration, now: now
        )

        guard fiveHourArtifact || sevenDayArtifact else { return self }

        let bindingCleared = bindingValue(fiveHour: fiveHourArtifact, sevenDay: sevenDayArtifact)

        return RateLimitUsage(
            representativeClaim: representativeClaim,
            fiveHourUtilization: fiveHourArtifact ? 0 : fiveHourUtilization,
            fiveHourReset: fiveHourReset,
            fiveHourStatus: fiveHourArtifact ? "allowed" : fiveHourStatus,
            sevenDayUtilization: sevenDayArtifact ? 0 : sevenDayUtilization,
            sevenDayReset: sevenDayReset,
            sevenDayStatus: sevenDayArtifact ? "allowed" : sevenDayStatus,
            overallStatus: bindingCleared ? "allowed" : overallStatus,
            provider: provider,
            fiveHourWindowMinutes: fiveHourWindowMinutes,
            sevenDayWindowMinutes: sevenDayWindowMinutes
        )
    }

    // MARK: - Countdown formatter

    /// Compact countdown string for menu bar: "2h 15m", "45m", "0s"
    static func countdownText(to date: Date, from now: Date = .now) -> String {
        DurationFormatter.compact(date.timeIntervalSince(now))
    }

    // MARK: - Predictive estimate

    /// Estimate time until the rate limit is reached for a given window,
    /// based on current utilization and time remaining until reset.
    /// Returns nil if utilization is too low or the estimate exceeds reset time.
    func estimatedTimeToLimit(for window: String) -> TimeInterval? {
        let (utilization, reset): (Double, Date?) = switch window {
        case Self.sevenDayWindow: (sevenDayUtilization, sevenDayReset)
        default: (fiveHourUtilization, fiveHourReset)
        }

        guard utilization > 0.20, let reset else { return nil }

        let remaining = reset.timeIntervalSinceNow
        guard remaining > 0 else { return nil }

        // Window duration inferred from window type
        let windowDuration: TimeInterval = window == Self.sevenDayWindow ? 7 * 24 * 3_600 : 5 * 3_600
        let elapsed = windowDuration - remaining

        guard elapsed > 60 else { return nil } // Need meaningful elapsed time

        // burn rate = utilization / elapsed, project when we reach 1.0
        let rate = utilization / elapsed
        let timeToFull = (1.0 - utilization) / rate

        // Only show if estimate is before the reset (otherwise it's fine)
        guard timeToFull < remaining else { return nil }

        return timeToFull
    }

    // MARK: - Parsing

    /// Parse unified rate limit headers from an HTTP response.
    /// Uses case-insensitive lookup to handle server-side casing changes
    /// (HTTPURLResponse.allHeaderFields bridging to Swift can lose case-insensitivity).
    static func parse(headers: [AnyHashable: Any]) -> RateLimitUsage? {
        // Build a lowercased lookup table for reliable case-insensitive access.
        let normalized: [String: String] = {
            var map = [String: String]()
            for (key, value) in headers {
                if let k = key as? String, let v = value as? String {
                    map[k.lowercased()] = v
                }
            }
            return map
        }()

        func stringHeader(_ key: String) -> String? {
            normalized[key.lowercased()]
        }

        func doubleHeader(_ key: String) -> Double {
            guard let val = normalized[key.lowercased()] else { return 0 }
            return Double(val) ?? 0
        }

        func dateFromUnix(_ key: String) -> Date? {
            guard let val = normalized[key.lowercased()],
                  let ts = TimeInterval(val),
                  ts > 0, ts < Date().timeIntervalSince1970 + 8 * 86_400 else { return nil }
            return Date(timeIntervalSince1970: ts)
        }

        // Detect unified headers
        guard let status = stringHeader("anthropic-ratelimit-unified-status") else {
            return nil
        }

        let representativeClaim = stringHeader("anthropic-ratelimit-unified-representative-claim") ?? fiveHourWindow

        return RateLimitUsage(
            representativeClaim: representativeClaim,
            fiveHourUtilization: min(max(doubleHeader("anthropic-ratelimit-unified-5h-utilization"), 0), 1),
            fiveHourReset: dateFromUnix("anthropic-ratelimit-unified-5h-reset"),
            fiveHourStatus: inferredWindowStatus(
                explicitStatus: stringHeader("anthropic-ratelimit-unified-5h-status"),
                overallStatus: status,
                representativeClaim: representativeClaim,
                window: fiveHourWindow
            ),
            sevenDayUtilization: min(max(doubleHeader("anthropic-ratelimit-unified-7d-utilization"), 0), 1),
            sevenDayReset: dateFromUnix("anthropic-ratelimit-unified-7d-reset"),
            sevenDayStatus: inferredWindowStatus(
                explicitStatus: stringHeader("anthropic-ratelimit-unified-7d-status"),
                overallStatus: status,
                representativeClaim: representativeClaim,
                window: sevenDayWindow
            ),
            overallStatus: status
        )
    }

    /// Parse Claude Code's JSON usage payload as a fallback when Anthropic no
    /// longer exposes unified 5h/7d windows in response headers.
    static func parse(clientData data: Data) -> RateLimitUsage? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return parse(clientDataJSON: json)
    }

    private static func parse(clientDataJSON json: Any) -> RateLimitUsage? {
        func normalizedKeys(from dictionary: [String: Any]) -> [String: Any] {
            var result: [String: Any] = [:]
            for (key, value) in dictionary {
                let normalized = key.lowercased().replacingOccurrences(of: "-", with: "_")
                result[normalized] = value
            }
            return result
        }

        func dictionary(_ value: Any?) -> [String: Any]? {
            guard let value = value as? [String: Any] else { return nil }
            return normalizedKeys(from: value)
        }

        func string(_ value: Any?) -> String? {
            if let value = value as? String, !value.isEmpty {
                return value
            }
            return nil
        }

        func parseDate(_ value: Any?) -> Date? {
            if let number = value as? NSNumber {
                let raw = number.doubleValue
                let seconds = raw > 10_000_000_000 ? raw / 1_000.0 : raw
                return Date(timeIntervalSince1970: seconds)
            }
            if let text = value as? String {
                if let unix = TimeInterval(text) {
                    let seconds = unix > 10_000_000_000 ? unix / 1_000.0 : unix
                    return Date(timeIntervalSince1970: seconds)
                }
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = iso.date(from: text) {
                    return date
                }
                iso.formatOptions = [.withInternetDateTime]
                if let date = iso.date(from: text) {
                    return date
                }
            }
            return nil
        }

        func parseUtilization(_ value: Any?) -> Double? {
            let raw: Double? = {
                if let number = value as? NSNumber {
                    return number.doubleValue
                }
                if let text = value as? String {
                    return Double(text)
                }
                return nil
            }()
            guard let raw else { return nil }
            let normalized = raw > 1.0 ? raw / 100.0 : raw
            return min(max(normalized, 0), 1)
        }

        func lookup(in json: Any, path: [String]) -> Any? {
            guard !path.isEmpty else { return json }
            guard let dict = dictionary(json) else { return nil }
            guard let value = dict[path[0]] else { return nil }
            return lookup(in: value, path: Array(path.dropFirst()))
        }

        func firstValue(in json: Any, paths: [[String]]) -> Any? {
            for path in paths {
                if let value = lookup(in: json, path: path) {
                    return value
                }
            }
            return nil
        }

        let fiveHourUtilization = parseUtilization(firstValue(in: json, paths: [
            ["rate_limits", "five_hour", "utilization"],
            ["rate_limits", "five_hour", "usage"],
            ["rate_limits", "5h", "utilization"],
            ["rate_limits", "5h", "usage"],
            ["usage", "five_hour", "utilization"],
            ["usage", "five_hour", "usage"],
            ["usage", "5h", "utilization"],
            ["usage", "5h", "usage"],
            ["five_hour", "utilization"],
            ["five_hour", "usage"],
            ["5h", "utilization"],
            ["5h", "usage"],
        ]))

        let sevenDayUtilization = parseUtilization(firstValue(in: json, paths: [
            ["rate_limits", "seven_day", "utilization"],
            ["rate_limits", "seven_day", "usage"],
            ["rate_limits", "7d", "utilization"],
            ["rate_limits", "7d", "usage"],
            ["usage", "seven_day", "utilization"],
            ["usage", "seven_day", "usage"],
            ["usage", "7d", "utilization"],
            ["usage", "7d", "usage"],
            ["seven_day", "utilization"],
            ["seven_day", "usage"],
            ["7d", "utilization"],
            ["7d", "usage"],
        ]))

        guard fiveHourUtilization != nil || sevenDayUtilization != nil else { return nil }

        let fiveHourReset = parseDate(firstValue(in: json, paths: [
            ["rate_limits", "five_hour", "reset"],
            ["rate_limits", "five_hour", "reset_at"],
            ["rate_limits", "five_hour", "resets_at"],
            ["rate_limits", "5h", "reset"],
            ["rate_limits", "5h", "reset_at"],
            ["usage", "five_hour", "reset"],
            ["usage", "five_hour", "reset_at"],
            ["usage", "five_hour", "resets_at"],
            ["usage", "5h", "reset"],
            ["usage", "5h", "reset_at"],
            ["five_hour", "reset"],
            ["five_hour", "reset_at"],
            ["five_hour", "resets_at"],
            ["5h", "reset"],
            ["5h", "reset_at"],
        ]))

        let sevenDayReset = parseDate(firstValue(in: json, paths: [
            ["rate_limits", "seven_day", "reset"],
            ["rate_limits", "seven_day", "reset_at"],
            ["rate_limits", "seven_day", "resets_at"],
            ["rate_limits", "7d", "reset"],
            ["rate_limits", "7d", "reset_at"],
            ["usage", "seven_day", "reset"],
            ["usage", "seven_day", "reset_at"],
            ["usage", "seven_day", "resets_at"],
            ["usage", "7d", "reset"],
            ["usage", "7d", "reset_at"],
            ["seven_day", "reset"],
            ["seven_day", "reset_at"],
            ["seven_day", "resets_at"],
            ["7d", "reset"],
            ["7d", "reset_at"],
        ]))

        let overallStatus = string(firstValue(in: json, paths: [
            ["rate_limits", "status"],
            ["usage", "status"],
            ["status"],
        ]))

        let fiveHourStatus = string(firstValue(in: json, paths: [
            ["rate_limits", "five_hour", "status"],
            ["rate_limits", "5h", "status"],
            ["usage", "five_hour", "status"],
            ["usage", "5h", "status"],
            ["five_hour", "status"],
            ["5h", "status"],
        ]))

        let sevenDayStatus = string(firstValue(in: json, paths: [
            ["rate_limits", "seven_day", "status"],
            ["rate_limits", "7d", "status"],
            ["usage", "seven_day", "status"],
            ["usage", "7d", "status"],
            ["seven_day", "status"],
            ["7d", "status"],
        ]))

        let representativeClaim = string(firstValue(in: json, paths: [
            ["rate_limits", "representative_claim"],
            ["rate_limits", "binding_window"],
            ["usage", "representative_claim"],
            ["usage", "binding_window"],
            ["representative_claim"],
            ["binding_window"],
        ])) ?? {
            let five = fiveHourUtilization ?? 0
            let seven = sevenDayUtilization ?? 0
            return seven > five ? sevenDayWindow : fiveHourWindow
        }()

        let inferredOverallStatus: String = {
            // Throttle is signalled ONLY by an explicit "throttled" status (or, elsewhere,
            // a real HTTP 429 via `markedThrottled`). 100% utilization means "at capacity",
            // not throttled — the user can typically keep working — so it must NOT synthesize
            // a throttled status here.
            if overallStatus == "throttled" || fiveHourStatus == "throttled" || sevenDayStatus == "throttled" {
                return "throttled"
            }
            return overallStatus ?? "allowed"
        }()

        let normalizedRepresentativeClaim = representativeClaim == sevenDayWindow ? sevenDayWindow : fiveHourWindow

        return RateLimitUsage(
            representativeClaim: normalizedRepresentativeClaim,
            fiveHourUtilization: fiveHourUtilization ?? 0,
            fiveHourReset: fiveHourReset,
            fiveHourStatus: inferredWindowStatus(
                explicitStatus: fiveHourStatus,
                overallStatus: inferredOverallStatus,
                representativeClaim: normalizedRepresentativeClaim,
                window: fiveHourWindow
            ),
            sevenDayUtilization: sevenDayUtilization ?? 0,
            sevenDayReset: sevenDayReset,
            sevenDayStatus: inferredWindowStatus(
                explicitStatus: sevenDayStatus,
                overallStatus: inferredOverallStatus,
                representativeClaim: normalizedRepresentativeClaim,
                window: sevenDayWindow
            ),
            overallStatus: inferredOverallStatus
        )
    }
}
