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
///
/// Caches results per account ID to support multi-account.
@MainActor
final class RateLimitFetcher {
    static let shared = RateLimitFetcher()

    private let messagesURL = URL(string: "https://api.anthropic.com/v1/messages?beta=true")!
    /// Per-account cache of API results.
    private var cachedResults: [String: APIFetchResult] = [:]
    /// Maximum age of cached result before it's considered stale and discarded.
    static let cacheMaxAge: TimeInterval = 3600 // 1 hour

    /// UserDefaults key prefix for persisted rate limits.
    private static let persistKeyPrefix = "aibattery_rateLimits_"

    /// Models to try in order. Free accounts may not have access to larger models,
    /// but rate limit headers come back the same regardless of model.
    private let models = [
        "claude-sonnet-4-6-20250929",
        "claude-sonnet-4-5-20250929",
        "claude-haiku-3-5-20241022",
        "claude-3-5-sonnet-20241022",
        "claude-3-haiku-20240307",
    ]

    /// Per-account model index (remembers last working model to avoid repeated fallbacks).
    private var currentModelIndex: [String: Int] = [:]

    private init() {
        restorePersistedRateLimits()
    }

    /// User-Agent string built from bundle version at startup.
    private let userAgent: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        return "AIBattery/\(version) (macOS)"
    }()

    /// Fetches rate limits + org profile for a specific account.
    func fetch(accessToken: String, accountId: String) async -> APIFetchResult {
        let startIndex = currentModelIndex[accountId] ?? 0

        // Try from the last-known-working model, then fall back through the list
        for i in startIndex..<models.count {
            let model = models[i]
            let result = await tryFetch(accessToken: accessToken, model: model, accountId: accountId)

            switch result {
            case .success(let fetchResult):
                currentModelIndex[accountId] = i
                cachedResults[accountId] = fetchResult
                persistRateLimits(fetchResult.rateLimits, fetchedAt: fetchResult.fetchedAt, accountId: accountId)
                AppLogger.network.info("RateLimitFetcher: success with \(model, privacy: .public), hasLimits=\(fetchResult.rateLimits != nil)")
                return fetchResult
            case .modelUnavailable:
                AppLogger.network.warning("RateLimitFetcher: model \(model, privacy: .public) unavailable, trying next")
                continue
            case .authFailed:
                AppLogger.network.error("RateLimitFetcher: auth failed for \(model, privacy: .public)")
                return cachedOrEmpty(accountId: accountId)
            case .networkError:
                AppLogger.network.error("RateLimitFetcher: network error for \(model, privacy: .public)")
                return cachedOrEmpty(accountId: accountId)
            }
        }

        // All models failed — return cached
        return cachedOrEmpty(accountId: accountId)
    }

    /// Return cached result marked as stale, or an empty result.
    /// Expires cache after `cacheMaxAge` to avoid showing very old data.
    func cachedOrEmpty(accountId: String) -> APIFetchResult {
        if let cached = cachedResults[accountId] {
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
            cachedResults.removeValue(forKey: accountId)
        }
        return APIFetchResult(rateLimits: nil, profile: nil)
    }

    /// Inject a cached result for testing.
    func setCachedResult(_ result: APIFetchResult, for accountId: String) {
        cachedResults[accountId] = result
    }

    /// Parse a Retry-After header value into a delay in seconds.
    /// Returns nil if the value is missing, non-numeric, zero, or negative.
    /// Caps at `maxDelay` to prevent unbounded waits.
    nonisolated static func parseRetryAfter(_ value: String?, maxDelay: Double = 30) -> Double? {
        guard let value, let delay = Double(value), delay > 0 else { return nil }
        return min(delay, maxDelay)
    }

    private enum FetchResult {
        case success(APIFetchResult)
        case modelUnavailable
        case authFailed
        case networkError
    }

    private func tryFetch(accessToken: String, model: String, accountId: String) async -> FetchResult {
        var request = URLRequest(url: messagesURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("oauth-2025-04-20,interleaved-thinking-2025-05-14", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": "."]],
            "max_tokens": 1
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            AppLogger.network.warning("RateLimitFetcher: failed to serialize request body")
            return .networkError
        }
        request.httpBody = bodyData

        // Cache lookup once — used as fallback when parsed headers are partial
        let cached = cachedResults[accountId]

        do {
            let (data, response) = try await SecureNetworking.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .networkError
            }

            // Auth failed — token may be expired/revoked
            if http.statusCode == 401 || http.statusCode == 403 {
                return .authFailed
            }

            // Rate limited — parse headers from the 429 itself (they're always present)
            if http.statusCode == 429 {
                let rateLimits = RateLimitUsage.parse(headers: http.allHeaderFields)
                let profile = APIProfile.parse(headers: http.allHeaderFields)
                if rateLimits != nil || profile != nil {
                    return .success(APIFetchResult(
                        rateLimits: rateLimits ?? cached?.rateLimits,
                        profile: profile ?? cached?.profile
                    ))
                }
                // No headers on 429 (unexpected) — fall through to retry
            }

            // Server error or headerless 429 — honor Retry-After if present
            if http.statusCode == 429 || (http.statusCode >= 500 && http.statusCode < 600) {
                if let delay = Self.parseRetryAfter(http.value(forHTTPHeaderField: "Retry-After")) {
                    try? await Task.sleep(for: .seconds(delay))
                    // Bail if the task was cancelled during sleep (account switch, app sleep, etc.)
                    guard !Task.isCancelled else { return cached.map { .success($0) } ?? .networkError }
                    if let (_, retryResp) = try? await SecureNetworking.data(for: request),
                       let retryHttp = retryResp as? HTTPURLResponse,
                       retryHttp.statusCode == 200 || retryHttp.statusCode == 400 {
                        let rateLimits = RateLimitUsage.parse(headers: retryHttp.allHeaderFields)
                        let profile = APIProfile.parse(headers: retryHttp.allHeaderFields)
                        if rateLimits != nil || profile != nil {
                            return .success(APIFetchResult(
                                rateLimits: rateLimits ?? cached?.rateLimits,
                                profile: profile ?? cached?.profile
                            ))
                        }
                    }
                }
                return .networkError
            }

            // Model not available for this account (400 with invalid model, or 404)
            if http.statusCode == 400 || http.statusCode == 404 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    let lower = message.lowercased()
                    if lower.contains("model") || lower.contains("access") {
                        return .modelUnavailable
                    }
                }
                // Try to extract rate limit headers even from error responses.
                let rateLimits = RateLimitUsage.parse(headers: http.allHeaderFields)
                if let rateLimits {
                    let profile = APIProfile.parse(headers: http.allHeaderFields)
                    return .success(APIFetchResult(
                        rateLimits: rateLimits,
                        profile: profile ?? cached?.profile
                    ))
                }
                // No headers — treat as model unavailable so we try the next model.
                return .modelUnavailable
            }

            // Parse both rate limits and org info from the same response headers
            let rateLimits = RateLimitUsage.parse(headers: http.allHeaderFields)
            let profile = APIProfile.parse(headers: http.allHeaderFields)

            let result = APIFetchResult(
                rateLimits: rateLimits ?? cached?.rateLimits,
                profile: profile ?? cached?.profile
            )
            return .success(result)
        } catch {
            return .networkError
        }
    }

    // MARK: - Rate limit persistence (survive app restart)

    /// Wrapper for persisting rate limits + fetch timestamp.
    private struct PersistedRateLimits: Codable {
        let rateLimits: RateLimitUsage
        let fetchedAt: Date
    }

    /// Save rate limits to UserDefaults for instant display on next launch.
    private func persistRateLimits(_ rateLimits: RateLimitUsage?, fetchedAt: Date, accountId: String) {
        guard let rateLimits else { return }
        let key = Self.persistKeyPrefix + accountId
        let persisted = PersistedRateLimits(rateLimits: rateLimits, fetchedAt: fetchedAt)
        if let data = try? JSONEncoder().encode(persisted) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Restore persisted rate limits into the in-memory cache on launch.
    /// Only restores if within cacheMaxAge — stale persisted data is discarded.
    private func restorePersistedRateLimits() {
        let defaults = UserDefaults.standard
        let prefix = Self.persistKeyPrefix
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            let accountId = String(key.dropFirst(prefix.count))
            guard let data = defaults.data(forKey: key),
                  let persisted = try? JSONDecoder().decode(PersistedRateLimits.self, from: data) else {
                defaults.removeObject(forKey: key)
                continue
            }
            let age = Date().timeIntervalSince(persisted.fetchedAt)
            if age < Self.cacheMaxAge {
                cachedResults[accountId] = APIFetchResult(
                    rateLimits: persisted.rateLimits,
                    profile: nil,
                    fetchedAt: persisted.fetchedAt,
                    isCached: true
                )
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

}
