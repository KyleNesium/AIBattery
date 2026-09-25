import Foundation

/// Which shape a Codex account's quota takes — drives the popover's bar layout and
/// the metric-picker vocabulary. Codex runs under three billing models:
///
/// - `.windows`   — ChatGPT subscriptions (Free / Plus / Pro / Team): 5-hour + weekly windows
/// - `.credits`   — spend-control plans (Business / Enterprise): one credit budget per period
/// - `.apiLimits` — API-key mode: pay-per-token, only per-minute request/token limits
enum CodexDisplayKind: Equatable, Sendable {
    case windows
    case credits
    case apiLimits

    static func of(rateLimits: RateLimitUsage?, standardLimits: StandardRateLimits?, apiKeyAccount: Bool) -> CodexDisplayKind {
        if rateLimits?.isCreditBudget == true {
            return .credits
        }
        if apiKeyAccount || (rateLimits == nil && standardLimits != nil) {
            return .apiLimits
        }
        return .windows
    }
}

/// How a Codex account authenticates. nil on persisted records means ChatGPT OAuth.
public enum CodexAccessMode: String, Codable, Sendable {
    case chatgpt
    case apiKey
}
