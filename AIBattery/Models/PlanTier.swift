import Foundation

/// Claude subscription plan tiers with estimated 5h/7d token limits.
///
/// Absolute limits are not published by Anthropic — these are community-derived
/// estimates. They serve as defaults until auto-calibrated by a 429 event or
/// restored API utilization headers (see `LocalUsageEstimate.calibrate`).
enum PlanTier: String, CaseIterable, Codable {
    case pro
    case max5x
    case max20x
    case team

    /// User-facing label.
    var displayName: String {
        switch self {
        case .pro: "Pro"
        case .max5x: "Max 5×"
        case .max20x: "Max 20×"
        case .team: "Team"
        }
    }

    /// Estimated 5-hour token budget (all token types: input + output + cache).
    /// Community-derived estimates — auto-calibrated when a 429 is detected.
    var estimatedFiveHourLimit: Int {
        switch self {
        case .pro: 7_000_000
        case .max5x: 35_000_000
        case .max20x: 140_000_000
        case .team: 10_000_000
        }
    }

    /// Estimated 7-day token budget (all token types: input + output + cache).
    var estimatedSevenDayLimit: Int {
        switch self {
        case .pro: 35_000_000
        case .max5x: 175_000_000
        case .max20x: 700_000_000
        case .team: 50_000_000
        }
    }

    /// Map an account's API-reported `billingType` string to a tier.
    /// Matching is conservative: lowercased with separators stripped, exact names
    /// only — an unrecognized billing string returns nil rather than guessing.
    init?(billingType: String) {
        let normalized = billingType.lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        switch normalized {
        case "pro": self = .pro
        case "max5x": self = .max5x
        case "max20x": self = .max20x
        case "team", "teams": self = .team
        default: return nil
        }
    }

    // MARK: - Persistence

    /// The user's selected plan tier (nil = not yet chosen).
    static var current: PlanTier? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: UserDefaultsKeys.planTier) else { return nil }
            return PlanTier(rawValue: raw)
        }
        set {
            UserDefaults.standard.set(newValue?.rawValue, forKey: UserDefaultsKeys.planTier)
        }
    }

    /// The tier to use for a specific account's estimates: the account's
    /// API-reported `billingType` when it maps to a known tier, else the
    /// user-selected global tier. With mixed-tier accounts, the global
    /// selection only describes one of them — prefer per-account truth.
    /// Reads the persisted account records directly so nonisolated estimate
    /// paths don't have to cross into the @MainActor `AccountStore`.
    static func effective(
        forAccountId accountId: String?,
        defaults: UserDefaults = .standard
    ) -> PlanTier? {
        if let accountId,
           let data = defaults.data(forKey: UserDefaultsKeys.accounts),
           let billing = claudeBillingTypes(in: data)[accountId],
           let tier = PlanTier(billingType: billing) {
            return tier
        }
        return current
    }

    // MARK: - Accounts-blob decode cache (perf backlog #9)

    /// `effective` is read several times per popover render in local-estimate mode.
    /// Decoding the persisted `[AccountRecord]` JSON each time was the cost; the blob
    /// only changes when an account is added/renamed/re-billed, so cache the decoded
    /// `accountId → billingType` map for the last blob seen (Data equality is a cheap
    /// memcmp). Claude accounts only — Codex plans never map to Claude tiers.
    /// Keyed by blob so concurrent readers of different blobs (parallel tests; a
    /// mid-write race in production) never evict each other. Production holds one
    /// entry; the cap only bounds pathological churn.
    nonisolated(unsafe) private static var decodedAccounts: [Data: [String: String]] = [:]
    nonisolated(unsafe) private static var decodeCounts: [Data: Int] = [:]
    private static let decodeLock = NSLock()
    private static let decodedAccountsCap = 8

    private static func claudeBillingTypes(in data: Data) -> [String: String] {
        decodeLock.lock()
        defer { decodeLock.unlock() }
        if let cached = decodedAccounts[data] {
            return cached
        }
        decodeCounts[data, default: 0] += 1
        let records = (try? JSONDecoder().decode([AccountRecord].self, from: data)) ?? []
        var billing: [String: String] = [:]
        for record in records where record.provider == .claude {
            if let type = record.billingType {
                billing[record.id] = type
            }
        }
        if decodedAccounts.count >= decodedAccountsCap {
            decodedAccounts.removeAll(keepingCapacity: true)
        }
        decodedAccounts[data] = billing
        return billing
    }

    /// How many times a given accounts blob has been decoded (tests pin decode-once).
    static func accountsDecodeCountForTesting(for data: Data) -> Int {
        decodeLock.lock()
        defer { decodeLock.unlock() }
        return decodeCounts[data] ?? 0
    }
}
