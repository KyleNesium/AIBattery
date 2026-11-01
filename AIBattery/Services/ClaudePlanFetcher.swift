import Foundation

/// Looks up each Claude account's plan from Anthropic's OAuth profile, once per launch,
/// so a Claude card can say "· Max 20×" the way a Codex card says "· Business".
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
        /// The profile answered. `nil` means it named no plan this app recognises.
        case answered(String?)
        /// The request was refused (401/403/404). Not retried this launch.
        case rejected
        /// Throttled, a server error or no response. Retried on a later cycle.
        case unavailable
    }

    /// Accounts whose lookup finished this launch (answered or rejected).
    private var settled: Set<String> = []
    private var inFlight: Set<String> = []

    /// Claude accounts that still need a lookup: identity resolved (a pending id is
    /// about to change), signed in, and not already settled this launch.
    nonisolated static func accountsNeedingPlan(
        _ accounts: [AccountRecord],
        settled: Set<String>,
        isAuthenticated: (String) -> Bool
    ) -> [String] {
        accounts
            .filter { $0.provider == .claude && !$0.isPendingIdentity }
            .map(\.id)
            .filter { !settled.contains($0) && isAuthenticated($0) }
    }

    /// Pure interpretation of a profile response, testable without the network.
    nonisolated static func interpret(statusCode: Int, data: Data) -> Outcome {
        switch statusCode {
        case 200..<300: .answered(ClaudePlan.billingType(fromProfile: data))
        case 401, 403, 404: .rejected
        default: .unavailable
        }
    }

    /// Fire-and-forget from the refresh tail: never delays a refresh, and a second call
    /// while one is running skips the accounts already being looked up.
    func syncPlans(oauthManager: OAuthManager) {
        let ids = Self.accountsNeedingPlan(
            oauthManager.accountStore.accounts,
            settled: settled.union(inFlight),
            isAuthenticated: { oauthManager.isAuthenticated(accountId: $0) }
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
        case let .answered(plan):
            settled.insert(accountId)
            // Only a recognised plan is written. An unrecognised answer leaves the stored
            // value alone rather than erasing a plan the profile merely failed to name.
            if let plan, oauthManager.accountStore.account(id: accountId)?.billingType != plan {
                oauthManager.updateAccountMetadata(accountId: accountId, billingType: plan)
            }
        case .rejected:
            settled.insert(accountId)
        case .unavailable:
            break
        }
        AppLogger.network.info("claude plan lookup \(accountId, privacy: .public): \(String(describing: outcome), privacy: .public)")
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
