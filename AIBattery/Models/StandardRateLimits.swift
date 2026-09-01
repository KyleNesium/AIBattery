import Foundation

/// Parsed from standard Anthropic API rate limit headers (per-minute/per-model).
/// These are always present in API responses, unlike the unified 5h/7d headers
/// which are only available for Claude Code accounts.
///
/// Used as a fallback display when unified rate limit headers are unavailable.
struct StandardRateLimits: Equatable, Codable {
    let requestsLimit: Int
    let requestsRemaining: Int
    let requestsReset: Date?

    let tokensLimit: Int
    let tokensRemaining: Int
    let tokensReset: Date?

    /// Requests utilization as percentage (0–100).
    var requestsPercent: Double {
        guard requestsLimit > 0 else { return 0 }
        return Double(requestsLimit - requestsRemaining) / Double(requestsLimit) * 100.0
    }

    /// Tokens utilization as percentage (0–100).
    var tokensPercent: Double {
        guard tokensLimit > 0 else { return 0 }
        return Double(tokensLimit - tokensRemaining) / Double(tokensLimit) * 100.0
    }

    /// Whether the account is at or near the request limit.
    var isRequestsExhausted: Bool { requestsRemaining <= 0 }

    /// Whether the account is at or near the token limit.
    var isTokensExhausted: Bool { tokensRemaining <= 0 }

    // MARK: - Parsing

    /// Parse standard rate limit headers from an HTTP response.
    static func parse(headers: [AnyHashable: Any]) -> StandardRateLimits? {
        let normalized: [String: String] = {
            var map = [String: String]()
            for (key, value) in headers {
                if let k = key as? String, let v = value as? String {
                    map[k.lowercased()] = v
                }
            }
            return map
        }()

        func intHeader(_ keys: String...) -> Int? {
            for key in keys {
                if let val = normalized[key.lowercased()], let n = Int(val) {
                    return n
                }
            }
            return nil
        }

        func dateHeader(_ keys: String...) -> Date? {
            for key in keys {
                guard let val = normalized[key.lowercased()] else { continue }
                // ISO 8601 timestamps
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = iso.date(from: val) {
                    return date
                }
                iso.formatOptions = [.withInternetDateTime]
                if let date = iso.date(from: val) {
                    return date
                }
                // Unix timestamps
                if let ts = TimeInterval(val) {
                    return Date(timeIntervalSince1970: ts)
                }
            }
            return nil
        }

        // Try standard requests headers first, fall back to input-tokens as proxy
        let requestsLimit = intHeader(
            "anthropic-ratelimit-requests-limit",
            "anthropic-ratelimit-input-tokens-limit"
        )
        let requestsRemaining = intHeader(
            "anthropic-ratelimit-requests-remaining",
            "anthropic-ratelimit-input-tokens-remaining"
        )

        // Need at least one limit/remaining pair to show anything useful
        let tokensLimit = intHeader(
            "anthropic-ratelimit-tokens-limit",
            "anthropic-ratelimit-output-tokens-limit"
        )
        let tokensRemaining = intHeader(
            "anthropic-ratelimit-tokens-remaining",
            "anthropic-ratelimit-output-tokens-remaining"
        )

        guard (requestsLimit != nil && requestsRemaining != nil)
            || (tokensLimit != nil && tokensRemaining != nil) else {
            return nil
        }

        return StandardRateLimits(
            requestsLimit: requestsLimit ?? 0,
            requestsRemaining: requestsRemaining ?? 0,
            requestsReset: dateHeader(
                "anthropic-ratelimit-requests-reset",
                "anthropic-ratelimit-input-tokens-reset"
            ),
            tokensLimit: tokensLimit ?? 0,
            tokensRemaining: tokensRemaining ?? 0,
            tokensReset: dateHeader(
                "anthropic-ratelimit-tokens-reset",
                "anthropic-ratelimit-output-tokens-reset"
            )
        )
    }
}
