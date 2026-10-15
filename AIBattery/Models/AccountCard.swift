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
        /// Tokens spent in this window, when the provider's local data has been
        /// aggregated this launch. Per provider, not per account — every account of a
        /// provider shares its session logs, same as the detail view.
        var tokens: Int?
    }

    let id: String
    let provider: AIProvider
    let identity: String
    let plan: String?
    let isActive: Bool
    /// Only set when the provider is actually having trouble. A green dot on every
    /// healthy card is noise — the dot is an exception marker, not a status readout.
    let status: StatusIndicator?
    /// The number the card leads with: the fuller window, the budget, or the busier
    /// per-minute limit. nil when there is no reading or no cap.
    let worstPercent: Double?
    let bars: [BarRow]
    let state: State
    /// Reset of the window the card leads with — shown on the state line, so the rows
    /// stay narrow enough for a token column.
    let reset: Date?
    /// Tokens spent today on this account's provider. Shown on the state line for the
    /// quota shapes whose rows carry no token figure of their own (a credit budget is
    /// spend, not tokens; API-key rows are per-minute), so every card says how much has
    /// actually been used. Per provider, like every other local figure.
    let tokensToday: Int?
    /// Most recent session activity on this account's provider — the moment the local
    /// logs last saw a turn. The overview breathes a dot beside the name while this is
    /// within `liveActivityWindow`: the one thing a list of accounts can't otherwise say
    /// is which one your CLI is using right now. Per provider.
    let lastActivity: Date?

    /// How recent activity has to be to count as "now".
    static let liveActivityWindow: TimeInterval = 5 * 60

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
        snapshots: [AIProvider: UsageSnapshot] = [:],
        isAuthenticated: (String) -> Bool,
        maskEmail: Bool
    ) -> [AccountCard] {
        AccountStore.displayOrdered(accounts)
            .filter { !$0.isPendingIdentity }
            .map { account in
                let index = AccountStore.providerIndex(of: account, in: accounts)
                let identity = AccountStore.identityLabel(for: account, providerIndex: index, maskEmail: maskEmail)
                let plan = account.provider == .codex ? AccountStore.planLabel(account.billingType) : nil
                let status = alertingStatus(statuses[account.provider]?.indicator)
                let active = account.id == activeId

                guard isAuthenticated(account.id) else {
                    return AccountCard(
                        id: account.id, provider: account.provider, identity: identity, plan: plan,
                        isActive: active, status: status, worstPercent: nil, bars: [],
                        state: .signedOut, reset: nil, tokensToday: nil, lastActivity: nil
                    )
                }
                let reading = readings[account.id]
                let bars = barRows(for: account, reading: reading, snapshot: snapshots[account.provider])
                return AccountCard(
                    id: account.id, provider: account.provider, identity: identity, plan: plan,
                    isActive: active, status: status, worstPercent: reading?.worstPercent,
                    bars: bars, state: state(for: reading), reset: bindingReset(bars: bars, reading: reading),
                    tokensToday: tokensToday(bars: bars, snapshot: snapshots[account.provider]),
                    lastActivity: lastActivity(snapshots[account.provider])
                )
            }
    }

    /// One row per window the account actually has: 5-hour + weekly, a single credit
    /// budget, or the two per-minute API-key limits. Without a reading the rows are
    /// still laid out (empty tracks) so a card doesn't change shape on first fetch.
    private nonisolated static func barRows(
        for account: AccountRecord,
        reading: AccountReading?,
        snapshot: UsageSnapshot?
    ) -> [BarRow] {
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
            BarRow(
                label: "5-Hour", percent: windows.fiveHourPercent, reset: windows.fiveHourReset,
                uncapped: false, tokens: snapshot?.fiveHourWindowTokens(resetsAt: windows.fiveHourReset)
            ),
            BarRow(
                label: secondary, percent: windows.sevenDayPercent, reset: windows.sevenDayReset,
                uncapped: false, tokens: snapshot?.sevenDayWindowTokens(resetsAt: windows.sevenDayReset)
            ),
        ]
    }

    /// The newest `lastActivity` across the provider's tracked sessions.
    nonisolated static func lastActivity(_ snapshot: UsageSnapshot?) -> Date? {
        guard let snapshot else { return nil }
        let candidates = snapshot.topSessionHealths.compactMap(\.lastActivity)
            + [snapshot.tokenHealth?.lastActivity].compactMap { $0 }
        return candidates.max()
    }

    /// Whether the provider counts as in use right now.
    nonisolated static func isLive(lastActivity: Date?, now: Date) -> Bool {
        guard let lastActivity else { return false }
        return now.timeIntervalSince(lastActivity) < liveActivityWindow
    }

    /// Degraded or worse only. Operational, maintenance and unknown produce no dot:
    /// the overview should look calm until something is wrong.
    nonisolated static func alertingStatus(_ indicator: StatusIndicator?) -> StatusIndicator? {
        guard let indicator else { return nil }
        return indicator.severity >= StatusIndicator.degradedPerformance.severity ? indicator : nil
    }

    /// Today's provider tokens, but only for the shapes whose rows show none — a
    /// windowed card already says 15M / 329M per window and doesn't need a third number.
    private nonisolated static func tokensToday(bars: [BarRow], snapshot: UsageSnapshot?) -> Int? {
        guard let snapshot, !bars.contains(where: { $0.tokens != nil }) else { return nil }
        let total = snapshot.todayModelTokens.reduce(0) { $0 + $1.totalTokens }
        return total > 0 ? total : nil
    }

    /// The reset the card's headline percent belongs to — the fuller window, the budget
    /// period, or the sooner per-minute reset.
    private nonisolated static func bindingReset(bars: [BarRow], reading: AccountReading?) -> Date? {
        guard let reading else { return nil }
        if reading.apiLimits != nil {
            return bars.compactMap(\.reset).min()
        }
        guard let worst = reading.worstPercent else { return bars.first?.reset }
        return bars.first(where: { $0.percent == worst })?.reset ?? bars.first?.reset
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

    /// The card's one line under the bars: what's wrong (or how long the headline window
    /// has left), today's usage where the rows don't already show it, and the reset.
    nonisolated static func stateLine(_ card: AccountCard, now: Date) -> String? {
        var parts: [String] = []
        if let state = stateText(card.state, now: now) {
            parts.append(state)
        }
        guard card.state != .signedOut else { return parts.first }
        if let tokens = card.tokensToday {
            parts.append("\(TokenFormatter.format(tokens)) today")
        }
        if let reset = card.reset, reset > now {
            parts.append("resets in \(DurationFormatter.compact(reset.timeIntervalSince(now)))")
        }
        guard !parts.isEmpty else { return nil }
        // The leading fragment opens the line; the rest read as clauses after it.
        let head = parts[0]
        let capitalised = head.prefix(1).uppercased() + head.dropFirst()
        return ([capitalised] + parts.dropFirst()).joined(separator: " \u{00B7} ")
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
            // Only mentioned when it is worth mentioning — `status` is nil while healthy.
            parts.append("\(provider.displayName) is reporting \(status.displayName)")
        }
        return parts.joined(separator: ", ")
    }
}
