import Foundation

/// Looks up each Claude account's plan **and sign-in email** from Anthropic's OAuth
/// profile, once per launch, so a Claude card can say "· Max 20×" the way a Codex card
/// says "· Business", and can name who it belongs to the way a Codex card does.
///
/// The email is here because this is the only Anthropic response that carries one — no
/// usage endpoint does, which is why a Claude account previously had nothing but a
/// workspace name, and nothing at all when the usage payload named no workspace.
///
/// Codex gets its plan for free on every usage poll (`plan_type`); none of the Claude
/// usage endpoints carry one, so this is a separate request. A plan almost never
/// changes, so the cost is one `GET` per Claude account per launch, off the refresh path,
/// and a set lookup on every cycle after that. The stored value persists in the account
/// blob, so the label is there on the next launch before the lookup runs.
@MainActor
final class ClaudePlanFetcher {
    static let shared = ClaudePlanFetcher()

    nonisolated static let profileURL = URL(string: "https://api.anthropic.com/api/oauth/profile")!

    enum Outcome: Equatable {
        /// The profile answered. Either field may be nil when the body names neither.
        case answered(ClaudeProfileFacts)
        /// The request was refused (401/403/404). Not retried this launch.
        case rejected
        /// Throttled, a server error or no response. Retried on a later cycle.
        case unavailable

        /// What may be written to the log. **Never the identity itself**: it is the
        /// account's sign-in email, and the default `description` of the associated
        /// `ClaudeProfileFacts` would print it in full — a `privacy: .public`
        /// interpolation of this outcome put it in the unified log in the clear. The
        /// plan is not a secret and is the half worth having; whether an email was
        /// found is enough to debug the other half.
        var logDescription: String {
            switch self {
            case let .answered(facts):
                "answered(plan: \(facts.billingType ?? "none"), identity: \(facts.identity == nil ? "none" : "present"))"
            case .rejected: "rejected"
            case .unavailable: "unavailable"
            }
        }
    }

    /// Accounts whose lookup finished this launch (answered or rejected).
    private var settled: Set<String> = []
    private var inFlight: Set<String> = []

    /// Per-account backoff for the one outcome that is *not* settled.
    ///
    /// `.unavailable` (429, 5xx, transport) leaves the account eligible, and `syncPlans`
    /// runs at the tail of every fan-out — so without this an Anthropic incident costs
    /// one extra profile GET per Claude account per poll for the rest of the launch,
    /// against an endpoint that is already failing. Every other network caller in the app
    /// sits on this same curve (60s → 300s cap, jittered).
    private var backoff: [String: EndpointBackoff] = [:]

    /// Claude accounts that still need a lookup: identity resolved (a pending id is
    /// about to change), signed in, and not already settled this launch.
    nonisolated static func accountsNeedingPlan(
        _ accounts: [AccountRecord],
        settled: Set<String>,
        isAuthenticated: (String) -> Bool,
        isBackingOff: (String) -> Bool = { _ in false }
    ) -> [String] {
        accounts
            .filter { $0.provider == .claude && !$0.isPendingIdentity }
            .map(\.id)
            .filter { !settled.contains($0) && isAuthenticated($0) && !isBackingOff($0) }
    }

    /// Pure interpretation of a profile response, testable without the network.
    nonisolated static func interpret(statusCode: Int, data: Data) -> Outcome {
        switch statusCode {
        case 200..<300: .answered(ClaudePlan.facts(fromProfile: data))
        case 401, 403, 404: .rejected
        default: .unavailable
        }
    }

    /// Fire-and-forget from the refresh tail: never delays a refresh, and a second call
    /// while one is running skips the accounts already being looked up.
    func syncPlans(oauthManager: OAuthManager) {
        let now = Date()
        let ids = Self.accountsNeedingPlan(
            oauthManager.accountStore.accounts,
            settled: settled.union(inFlight),
            isAuthenticated: { oauthManager.isAuthenticated(accountId: $0) },
            isBackingOff: { [backoff] in EndpointBackoff.shouldSkip(backoff[$0] ?? EndpointBackoff(), now: now) }
        )
        guard !ids.isEmpty else { return }
        inFlight.formUnion(ids)
        Task { [weak self] in
            for id in ids {
                await self?.sync(accountId: id, oauthManager: oauthManager)
            }
        }
    }

    private func sync(accountId: String, oauthManager: OAuthManager) async {
        defer { inFlight.remove(accountId) }
        guard let token = await oauthManager.getAccessToken(for: accountId) else { return }
        let outcome = await fetch(accessToken: token)
        switch outcome {
        case let .answered(facts):
            settled.insert(accountId)
            backoff[accountId] = nil
            // Only a recognised plan is written. An unrecognised answer leaves the stored
            // value alone rather than erasing a plan the profile merely failed to name.
            if let plan = facts.billingType, oauthManager.accountStore.account(id: accountId)?.billingType != plan {
                oauthManager.updateAccountMetadata(accountId: accountId, billingType: plan)
            }
            // Same request, same rule: this is where a Claude account finally gets a
            // sign-in email. Nothing else in Anthropic's OAuth surface carries one, so
            // without it "Show account email" had nothing to show for Claude.
            if let identity = facts.identity, oauthManager.accountStore.account(id: accountId)?.discoveredIdentity != identity {
                oauthManager.updateAccountMetadata(accountId: accountId, discoveredIdentity: identity)
            }
        case .rejected:
            settled.insert(accountId)
            backoff[accountId] = nil
        case .unavailable:
            // Not settled — the plan is still unknown and worth another try — but not on
            // the very next poll.
            backoff[accountId] = EndpointBackoff.recordingFailure(
                backoff[accountId] ?? EndpointBackoff(), now: Date()
            )
        }
        AppLogger.network.info("claude plan lookup \(accountId, privacy: .public): \(outcome.logDescription, privacy: .public)")
    }

    private func fetch(accessToken: String) async -> Outcome {
        var request = URLRequest(url: Self.profileURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(RateLimitFetcher.shared.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
        do {
            let (data, response) = try await SecureNetworking.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .unavailable }
            return Self.interpret(statusCode: http.statusCode, data: data)
        } catch {
            return .unavailable
        }
    }
}
