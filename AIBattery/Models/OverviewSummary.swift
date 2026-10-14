import Foundation

/// The one line under the overview's title. It earns its space by saying something no
/// individual card does: how much has been spent across every account today, when the
/// next window frees up, and — ahead of both — whether an account needs attention.
struct OverviewSummary: Equatable {
    /// Identities that are throttled or at their limit, in card order.
    let needsAttention: [String]
    /// Tokens spent today across every provider that has been aggregated this launch.
    /// nil until at least one has. Tokens are tokens — this is volume, not cost.
    let tokensToday: Int?
    /// Soonest reset across every card.
    let nextReset: Date?

    static func make(cards: [AccountCard], snapshots: [AIProvider: UsageSnapshot]) -> OverviewSummary {
        let attention = cards
            .filter { $0.state == .throttled || $0.state == .limitReached }
            .map(\.identity)
        // Per provider, not per card: every account of a provider shares its session logs,
        // so summing per card would count the same tokens twice.
        let providers = Set(cards.map(\.provider))
        let totals = providers.compactMap { provider -> Int? in
            guard let snapshot = snapshots[provider] else { return nil }
            return snapshot.todayModelTokens.reduce(0) { $0 + $1.totalTokens }
        }
        return OverviewSummary(
            needsAttention: attention,
            tokensToday: totals.isEmpty ? nil : totals.reduce(0, +),
            nextReset: cards.compactMap(\.reset).min()
        )
    }

    /// Trouble first — a throttled account is the only thing worth reading here when it
    /// exists. Otherwise today's volume and the next reset.
    func text(now: Date) -> String? {
        if let first = needsAttention.first {
            return needsAttention.count == 1
                ? "\(first) needs attention"
                : "\(needsAttention.count) accounts need attention"
        }
        var parts: [String] = []
        if let tokensToday, tokensToday > 0 {
            parts.append("\(TokenFormatter.format(tokensToday)) today")
        }
        if let nextReset, nextReset > now {
            parts.append("next reset in \(DurationFormatter.compact(nextReset.timeIntervalSince(now)))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    var isAlarm: Bool { !needsAttention.isEmpty }
}
