import Foundation

/// Everything one overview card shows, computed from the account store, the fan-out
/// readings and the provider statuses. Pure, so the whole card — order, labels, the
/// number it leads with, its state line — is testable without AppKit.
///
/// Cards carry **quota only**. Insights, Projects and Context come from machine-wide
/// per-provider logs, so a per-account value there would be fabricated.
struct AccountCard: Identifiable, Equatable {
    /// The one line under the bars, when there is something worth saying.
    enum State: Equatable {
        case throttled
        case limitReached
        case signedOut
        case timeToLimit(TimeInterval)
        case cached(Date)
        case fetching
        case none
    }

    struct BarRow: Equatable {
        let label: String
        /// 0…100; nil = no reading yet (empty track, "—").
        let percent: Double?
        let reset: Date?
        /// Credit budget with no spend cap: nothing to meter.
        let uncapped: Bool
    }

    let id: String
    let provider: AIProvider
    let identity: String
    let plan: String?
    let isActive: Bool
    let status: StatusIndicator?
    /// The number the card leads with: the fuller window, the budget, or the busier
    /// per-minute limit. nil when there is no reading or no cap.
    let worstPercent: Double?
    let bars: [BarRow]
    let state: State

    /// Accounts the overview lists, and the count the popover's mode is decided from:
    /// identity resolved. Signed-out accounts stay in — they become sign-in cards,
    /// which is exactly what a multi-account user needs to notice.
    nonisolated static func eligibleCount(accounts: [AccountRecord]) -> Int {
        accounts.filter { !$0.isPendingIdentity }.count
    }

    nonisolated static func rows(
        accounts: [AccountRecord],
        activeId: String?,
        readings: [String: AccountReading],
        statuses: [AIProvider: ClaudeSystemStatus],
        isAuthenticated: (String) -> Bool,
        maskEmail: Bool,
        now: Date
    ) -> [AccountCard] {
        AccountStore.displayOrdered(accounts)
            .filter { !$0.isPendingIdentity }
            .map { account in
                let index = AccountStore.providerIndex(of: account, in: accounts)
                let identity = AccountStore.identityLabel(for: account, providerIndex: index, maskEmail: maskEmail)
                let plan = account.provider == .codex ? AccountStore.planLabel(account.billingType) : nil
                let status = statuses[account.provider]?.indicator
                let active = account.id == activeId

                guard isAuthenticated(account.id) else {
                    return AccountCard(
                        id: account.id, provider: account.provider, identity: identity, plan: plan,
                        isActive: active, status: status, worstPercent: nil, bars: [], state: .signedOut
                    )
                }
                let reading = readings[account.id]
                return AccountCard(
                    id: account.id, provider: account.provider, identity: identity, plan: plan,
                    isActive: active, status: status, worstPercent: reading?.worstPercent,
                    bars: barRows(for: account, reading: reading), state: state(for: reading)
                )
            }
    }

    /// One row per window the account actually has: 5-hour + weekly, a single credit
    /// budget, or the two per-minute API-key limits. Without a reading the rows are
    /// still laid out (empty tracks) so a card doesn't change shape on first fetch.
    private nonisolated static func barRows(for account: AccountRecord, reading: AccountReading?) -> [BarRow] {
        let secondary = account.provider.secondaryWindowLabel
        guard let reading else {
            if account.isAPIKeyAccount {
                return [
                    BarRow(label: "Requests", percent: nil, reset: nil, uncapped: false),
                    BarRow(label: "Tokens", percent: nil, reset: nil, uncapped: false),
                ]
            }
            return [
                BarRow(label: "5-Hour", percent: nil, reset: nil, uncapped: false),
                BarRow(label: secondary, percent: nil, reset: nil, uncapped: false),
            ]
        }
        if let std = reading.apiLimits {
            return [
                BarRow(label: "Requests", percent: std.requestsPercent, reset: std.requestsReset, uncapped: false),
                BarRow(label: "Tokens", percent: std.tokensPercent, reset: std.tokensReset, uncapped: false),
            ]
        }
        guard let windows = reading.windows else { return [] }
        if let budget = windows.creditBudget {
            return [BarRow(
                label: "Credits",
                percent: budget.isUncapped ? nil : budget.usedPercent,
                reset: budget.resetsAt,
                uncapped: budget.isUncapped
            )]
        }
        return [
            BarRow(label: "5-Hour", percent: windows.fiveHourPercent, reset: windows.fiveHourReset, uncapped: false),
            BarRow(label: secondary, percent: windows.sevenDayPercent, reset: windows.sevenDayReset, uncapped: false),
        ]
    }

    /// First match wins: throttled → limit reached → burn-rate estimate → cached → none.
    /// The alarm states go through `UsageBar.AlarmState` so a card can't alarm on data
    /// the bars would refuse to alarm on.
    private nonisolated static func state(for reading: AccountReading?) -> State {
        guard let reading else { return .fetching }
        let confirmed = !reading.isCached
        if let windows = reading.windows {
            let alarm = UsageBar.AlarmState(
                percent: reading.worstPercent ?? 0,
                isThrottled: windows.isThrottled,
                confirmed: confirmed
            )
            if alarm.throttled {
                return .throttled
            }
            if alarm.limitReached {
                return .limitReached
            }
            if confirmed, windows.creditBudget == nil {
                let binding = windows.fiveHourPercent >= windows.sevenDayPercent
                    ? RateLimitUsage.fiveHourWindow
                    : RateLimitUsage.sevenDayWindow
                if let eta = windows.estimatedTimeToLimit(for: binding) {
                    return .timeToLimit(eta)
                }
            }
        } else if let std = reading.apiLimits, std.isRequestsExhausted || std.isTokensExhausted {
            return .limitReached
        }
        if reading.isCached {
            return .cached(reading.fetchedAt)
        }
        return .none
    }

    nonisolated static func stateText(_ state: State, now: Date) -> String? {
        switch state {
        case .throttled: "Throttled"
        case .limitReached: "Limit reached"
        case .signedOut: "Signed out · click to sign in"
        case let .timeToLimit(eta): "~\(DurationFormatter.compact(eta)) to limit"
        case let .cached(at): "Cached \(Self.elapsedText(since: at, now: now))"
        case .fetching: "Fetching…"
        case .none: nil
        }
    }

    /// "3m ago" with an injected clock — `PopoverFooterView.relativeTime` reads the
    /// wall clock, which a pure card model must not do.
    nonisolated static func elapsedText(since: Date, now: Date) -> String {
        let elapsed = max(0, now.timeIntervalSince(since))
        if elapsed < 60 {
            return "just now"
        }
        if elapsed < 3_600 {
            return "\(Int(elapsed / 60))m ago"
        }
        if elapsed < 86_400 {
            return "\(Int(elapsed / 3_600))h ago"
        }
        return "\(Int(elapsed / 86_400))d ago"
    }

    var accessibilityLabel: String {
        var parts = ["\(provider.displayName) account \(identity)"]
        if let plan {
            parts.append(plan)
        }
        if isActive {
            parts.append("active")
        }
        for bar in bars {
            if let percent = bar.percent {
                parts.append("\(bar.label) \(Int(percent.rounded())) percent")
            } else if bar.uncapped {
                parts.append("\(bar.label) no cap")
            }
        }
        if let status {
            parts.append("\(provider.displayName) status \(status.rawValue)")
        }
        return parts.joined(separator: ", ")
    }
}
