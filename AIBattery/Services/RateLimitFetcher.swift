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


    /// UserDefaults key prefix for persisted rate limits.
    private static let persistKeyPrefix = "aibattery_rateLimits_"

    /// Single hardcoded model used as ultimate fallback for fresh installs with no JSONL data.
    /// Kept to the single newest model so fresh installs work without any prior usage history.
    static let ultimateFallback = "claude-sonnet-4-6-20250929"

    /// Dynamic list of model IDs observed in JSONL sessions, sorted by most-recently-seen first.
    /// Populated by UsageAggregator after each aggregation cycle. Replaces the old hardcoded
    /// list so the probe list self-heals when Anthropic deprecates model IDs.
    private(set) var observedModels: [String] = []
    private static let observedModelsKeyPrefix = "aibattery_observedModels_"

    /// Per-account last working model ID — persisted to UserDefaults so the app
    /// starts with a known-good model after restart instead of retrying from the top.
    private var lastWorkingModel: [String: String] = [:]
    private static let workingModelKeyPrefix = "aibattery_probeModel_"

    private init() {
        restorePersistedRateLimits()
        restoreWorkingModels()
    }

    private func restoreWorkingModels() {
        let defaults = UserDefaults.standard
        let prefix = Self.workingModelKeyPrefix
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            let accountId = String(key.dropFirst(prefix.count))
            if let model = defaults.string(forKey: key) {
                lastWorkingModel[accountId] = model
            }
        }
        // Also restore observed models from the active account's persisted list
        // (best-effort — overwritten on first aggregation).
        let activeAccountId = OAuthManager.shared.accountStore.activeAccountId
        if let activeAccountId,
           let models = defaults.stringArray(forKey: Self.observedModelsKeyPrefix + activeAccountId),
           !models.isEmpty {
            observedModels = models
        } else {
            // Fallback: try any persisted account's models so fresh fetches have a probe list
            let observedPrefix = Self.observedModelsKeyPrefix
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(observedPrefix) {
                if let models = defaults.stringArray(forKey: key), !models.isEmpty {
                    observedModels = models
                    break
                }
            }
        }
    }

    /// Persist observed models for the given account so they survive app restarts.
    /// Called by UsageAggregator after each aggregation cycle.
    func setObservedModels(_ models: [String], accountId: String) {
        observedModels = models
        UserDefaults.standard.set(models, forKey: Self.observedModelsKeyPrefix + accountId)
    }

    private func saveWorkingModel(_ model: String, accountId: String) {
        lastWorkingModel[accountId] = model
        UserDefaults.standard.set(model, forKey: Self.workingModelKeyPrefix + accountId)
    }

    /// User-Agent string built from bundle version at startup.
    private let userAgent: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        return "AIBattery/\(version) (macOS)"
    }()

    /// The model the user is actively running in Claude Code (from latest JSONL entry).
    /// Set by UsageAggregator after reading session logs.
    var activeUserModel: String?

    /// Fetches rate limits + org profile for a specific account.
    /// Probe order: user's active model → last working model → observedModels (JSONL) → ultimateFallback.
    func fetch(accessToken: String, accountId: String) async -> APIFetchResult {
        // Build probe list: active model first, then persisted working model,
        // then observed models from JSONL (most recent first), then the ultimate fallback.
        // Dedup so we don't try the same model twice.
        var probeModels: [String] = []
        var seen = Set<String>()
        for candidate in [activeUserModel, lastWorkingModel[accountId]].compactMap({ $0 }) + observedModels + [Self.ultimateFallback] {
            if seen.insert(candidate).inserted {
                probeModels.append(candidate)
            }
        }

        for model in probeModels {
            let result = await tryFetch(accessToken: accessToken, model: model, accountId: accountId)

            switch result {
            case .success(let fetchResult):
                saveWorkingModel(model, accountId: accountId)
                cachedResults[accountId] = fetchResult
                persistRateLimits(fetchResult.rateLimits, fetchedAt: fetchResult.fetchedAt, accountId: accountId)
                return fetchResult
            case .modelUnavailable:
                continue
            case .authFailed:
                return cachedOrEmpty(accountId: accountId)
            case .networkError:
                return cachedOrEmpty(accountId: accountId)
            }
        }

        // All models failed — return cached
        return cachedOrEmpty(accountId: accountId)
    }

    /// Return cached result marked as stale, or an empty result.
    /// Always returns cached data when available — stale rate limits are better
    /// than empty bars (e.g., after waking from long sleep with expired token).
    /// Fresh fetches replace the cache naturally on success.
    func cachedOrEmpty(accountId: String) -> APIFetchResult {
        if let cached = cachedResults[accountId] {
            return APIFetchResult(
                rateLimits: cached.rateLimits,
                profile: cached.profile,
                fetchedAt: cached.fetchedAt,
                isCached: true
            )
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
                    saveWorkingModel(model, accountId: accountId)
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
                            saveWorkingModel(model, accountId: accountId)
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
                    saveWorkingModel(model, accountId: accountId)
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
    /// Always restores — stale data is better than empty bars on wake from sleep.
    /// Fresh fetches replace stale data naturally on the first successful poll.
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
            cachedResults[accountId] = APIFetchResult(
                rateLimits: persisted.rateLimits,
                profile: nil,
                fetchedAt: persisted.fetchedAt,
                isCached: true
            )
        }
    }

}
