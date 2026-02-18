import Foundation

/// Fetches rate limit usage AND org profile by making a single minimal
/// Messages API call and parsing both the anthropic-ratelimit-* headers
/// and the x-organization-name header from the same response.
///
/// Uses OAuth Bearer token authentication (not API keys).
/// Requires the `oauth-2025-04-20` beta header for OAuth access.
///
/// Tries models in order of preference, falling back to cheaper models
/// if the account doesn't have access (e.g. free-tier users).
/// Rate limit headers are account-level, so any model works.
final class RateLimitFetcher {
    static let shared = RateLimitFetcher()

    private let messagesURL = URL(string: "https://api.anthropic.com/v1/messages?beta=true")!
    private var cachedResult: APIFetchResult?
    /// Maximum age of cached result before it's considered stale and discarded.
    private static let cacheMaxAge: TimeInterval = 3600 // 1 hour

    /// Models to try in order. Free accounts may not have access to larger models,
    /// but rate limit headers come back the same regardless of model.
    private let models = [
        "claude-sonnet-4-5-20250929",
        "claude-haiku-3-5-20241022",
    ]

    /// Which model index to use (remembers last working model to avoid repeated fallbacks).
    private var currentModelIndex = 0

    /// Fetches rate limits + org profile in a single API call.
    func fetch() async -> APIFetchResult {
        guard let accessToken = await OAuthManager.shared.getAccessToken() else {
            return cachedOrEmpty()
        }

        // Try from the last-known-working model, then fall back through the list
        for i in currentModelIndex..<models.count {
            let model = models[i]
            let result = await tryFetch(accessToken: accessToken, model: model)

            switch result {
            case .success(let fetchResult):
                currentModelIndex = i
                cachedResult = fetchResult
                return fetchResult
            case .modelUnavailable:
                // This model isn't available for this account — try the next one
                continue
            case .authFailed:
                return cachedOrEmpty()
            case .networkError:
                return cachedOrEmpty()
            }
        }

        // All models failed — return cached
        return cachedOrEmpty()
    }

    /// Return cached result marked as stale, or an empty result.
    /// Expires cache after `cacheMaxAge` to avoid showing very old data.
    private func cachedOrEmpty() -> APIFetchResult {
        if let cached = cachedResult {
            let age = Date().timeIntervalSince(cached.fetchedAt)
            if age < Self.cacheMaxAge {
                return APIFetchResult(
                    rateLimits: cached.rateLimits,
                    profile: cached.profile,
                    fetchedAt: cached.fetchedAt,
                    isCached: true
                )
            }
            // Cache too old — discard it
            cachedResult = nil
        }
        return APIFetchResult(rateLimits: nil, profile: nil)
    }

    private enum FetchResult {
        case success(APIFetchResult)
        case modelUnavailable
        case authFailed
        case networkError
    }

    private func tryFetch(accessToken: String, model: String) async -> FetchResult {
        var request = URLRequest(url: messagesURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("oauth-2025-04-20,interleaved-thinking-2025-05-14", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("AIBattery/1.0.0 (macOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": "."]],
            "max_tokens": 1
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .networkError
            }

            // Auth failed — token may be expired/revoked
            if http.statusCode == 401 || http.statusCode == 403 {
                return .authFailed
            }

            // Model not available for this account (400 with invalid model, or 404)
            if http.statusCode == 400 || http.statusCode == 404 {
                // Check if it's specifically a model-access error
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? [String: Any],
                   let message = error["message"] as? String,
                   message.lowercased().contains("model") || message.lowercased().contains("access") {
                    return .modelUnavailable
                }
                // Rate limit headers may still be present even on error responses
            }

            // Parse both rate limits and org info from the same response headers
            let rateLimits = RateLimitUsage.parse(headers: http.allHeaderFields)
            let profile = APIProfile.parse(headers: http.allHeaderFields)

            let result = APIFetchResult(
                rateLimits: rateLimits ?? cachedResult?.rateLimits,
                profile: profile ?? cachedResult?.profile
            )
            return .success(result)
        } catch {
            return .networkError
        }
    }

}
