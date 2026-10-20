import Foundation

/// Which Codex account's turns an aggregation counts.
///
/// `.all` is every entry on disk — the only mode for Claude, for API-key accounts and
/// for setups with at most one ChatGPT-backed Codex account. `.account(id)` keeps the
/// entries whose rollout `session_meta` was stamped with that ChatGPT account id
/// (current Codex CLI versions write it; older rollouts carry no stamp).
///
///     entries ─┬─ stamped id      → kept
///              ├─ no stamp (old)  → dropped, counted as unattributed
///              └─ other account   → dropped, uncounted
enum Attribution: Hashable, Sendable {
    case all
    case account(String)

    var isAttributed: Bool {
        if case .account = self {
            return true
        }
        return false
    }

    /// Under `.all` the input is returned untouched (no copy). The kept array keeps the
    /// reader's ascending timestamp order, which every consumer relies on.
    func partition(_ entries: [AssistantUsageEntry]) -> (kept: [AssistantUsageEntry], unattributed: Int) {
        guard case let .account(id) = self else { return (entries, 0) }
        var kept: [AssistantUsageEntry] = []
        kept.reserveCapacity(entries.count)
        var unattributed = 0
        for entry in entries {
            switch entry.creatorAccountId {
            case let .some(stamp) where stamp == id: kept.append(entry)
            case .none: unattributed += 1
            default: break
            }
        }
        return (kept, unattributed)
    }
}
