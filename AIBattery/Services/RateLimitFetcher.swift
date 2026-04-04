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
    private let clientDataURL = URL(string: "https://api.anthropic.com/api/oauth/claude_cli/client_data")!
    /// Per-account cache of API results. Never expires — stale data is better than empty bars.
    /// Fresh fetches replace cached data on success.
    private var cachedResults: [String: APIFetchResult] = [:]

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
                persistRateLimits(fetchResult, accountId: accountId)
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
                rateLimitSource: cached.rateLimitSource,
                standardLimits: cached.standardLimits,
                profile: cached.profile,
                hasStandardRateLimitHeaders: cached.hasStandardRateLimitHeaders,
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
            let hasStandardRateLimitHeaders = Self.containsStandardRateLimitHeaders(http.allHeaderFields)
            let standardLimits = StandardRateLimits.parse(headers: http.allHeaderFields)

            // Auth failed — token may be expired/revoked
            if http.statusCode == 401 || http.statusCode == 403 {
                return .authFailed
            }

            // Rate limited — parse headers from the 429 itself
            if http.statusCode == 429 {
                let rateLimits = RateLimitUsage.parse(headers: http.allHeaderFields)
                let profile = APIProfile.parse(headers: http.allHeaderFields)
                if let rateLimits {
                    let throttledRateLimits = rateLimits.markedThrottled()
                    saveWorkingModel(model, accountId: accountId)
                    return .success(APIFetchResult(
                        rateLimits: throttledRateLimits,
                        rateLimitSource: .anthropicAPIHeaders,
                        standardLimits: standardLimits,
                        profile: profile ?? cached?.profile,
                        hasStandardRateLimitHeaders: hasStandardRateLimitHeaders
                    ))
                }

                if let fallback = await fetchClaudeCodeClientData(
                    accessToken: accessToken,
                    cached: cached,
                    accountId: accountId,
                    model: model,
                    callerStandardLimits: standardLimits
                ) {
                    return .success(fallback)
                }

                if profile != nil || hasStandardRateLimitHeaders {
                    return .success(APIFetchResult(
                        rateLimits: nil,
                        standardLimits: standardLimits,
                        profile: profile ?? cached?.profile,
                        hasStandardRateLimitHeaders: hasStandardRateLimitHeaders
                    ))
                }

                // 429 without any rate limit data — Anthropic may have removed
                // unified headers. Return success with nil rateLimits so the UI
                // shows the unavailable state rather than spinning forever.
                AppLogger.network.warning("429 without rate limit headers (model=\(model))")

                // Honor Retry-After if present
                if let delay = Self.parseRetryAfter(http.value(forHTTPHeaderField: "Retry-After")) {
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled else { return cached.map { .success($0) } ?? .networkError }
                    if let (_, retryResp) = try? await SecureNetworking.data(for: request),
                       let retryHttp = retryResp as? HTTPURLResponse {
                        let retryRL = RateLimitUsage.parse(headers: retryHttp.allHeaderFields)
                        let retryProfile = APIProfile.parse(headers: retryHttp.allHeaderFields)
                        let retryStdLimits = StandardRateLimits.parse(headers: retryHttp.allHeaderFields)
                        if let retryRL {
                            let throttledRetryRL = retryHttp.statusCode == 429
                                ? retryRL.markedThrottled()
                                : retryRL
                            saveWorkingModel(model, accountId: accountId)
                            return .success(APIFetchResult(
                                rateLimits: throttledRetryRL,
                                rateLimitSource: .anthropicAPIHeaders,
                                standardLimits: retryStdLimits,
                                profile: retryProfile ?? cached?.profile,
                                hasStandardRateLimitHeaders: Self.containsStandardRateLimitHeaders(retryHttp.allHeaderFields)
                            ))
                        }

                        if let fallback = await fetchClaudeCodeClientData(
                            accessToken: accessToken,
                            cached: cached,
                            accountId: accountId,
                            model: model,
                            callerStandardLimits: retryStdLimits ?? standardLimits
                        ) {
                            return .success(fallback)
                        }

                        if retryProfile != nil || Self.containsStandardRateLimitHeaders(retryHttp.allHeaderFields) {
                            return .success(APIFetchResult(
                                rateLimits: nil,
                                standardLimits: retryStdLimits,
                                profile: retryProfile ?? cached?.profile,
                                hasStandardRateLimitHeaders: Self.containsStandardRateLimitHeaders(retryHttp.allHeaderFields)
                            ))
                        }
                    }
                }

                // 429 with no data at all — return success with nil rateLimits
                // so the caller knows the API is reachable but usage data is unavailable.
                // This prevents cycling through all probe models for no reason.
                saveWorkingModel(model, accountId: accountId)
                return .success(APIFetchResult(
                    rateLimits: nil,
                    standardLimits: nil,
                    profile: profile ?? cached?.profile,
                    hasStandardRateLimitHeaders: false
                ))
            }

            // Server error — honor Retry-After if present, then try next model
            if http.statusCode >= 500 && http.statusCode < 600 {
                if let delay = Self.parseRetryAfter(http.value(forHTTPHeaderField: "Retry-After")) {
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled else { return cached.map { .success($0) } ?? .networkError }
                    if let (_, retryResp) = try? await SecureNetworking.data(for: request),
                       let retryHttp = retryResp as? HTTPURLResponse,
                       retryHttp.statusCode == 200 || retryHttp.statusCode == 400 {
                        let rateLimits = RateLimitUsage.parse(headers: retryHttp.allHeaderFields)
                        let profile = APIProfile.parse(headers: retryHttp.allHeaderFields)
                        let retryStdLimits = StandardRateLimits.parse(headers: retryHttp.allHeaderFields)
                        if rateLimits != nil || profile != nil {
                            saveWorkingModel(model, accountId: accountId)
                            return .success(APIFetchResult(
                                rateLimits: rateLimits,
                                rateLimitSource: rateLimits == nil ? nil : .anthropicAPIHeaders,
                                standardLimits: retryStdLimits,
                                profile: profile ?? cached?.profile,
                                hasStandardRateLimitHeaders: Self.containsStandardRateLimitHeaders(retryHttp.allHeaderFields)
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
                        rateLimitSource: .anthropicAPIHeaders,
                        standardLimits: standardLimits,
                        profile: profile ?? cached?.profile,
                        hasStandardRateLimitHeaders: hasStandardRateLimitHeaders
                    ))
                }
                // No headers — treat as model unavailable so we try the next model.
                return .modelUnavailable
            }

            // Parse both rate limits and org info from the same response headers
            let rateLimits = RateLimitUsage.parse(headers: http.allHeaderFields)
            let profile = APIProfile.parse(headers: http.allHeaderFields)

            if rateLimits == nil {
                let rlHeaders = http.allHeaderFields.keys
                    .compactMap { $0 as? String }
                    .filter { $0.lowercased().contains("ratelimit") }
                let found = rlHeaders.isEmpty ? "none" : rlHeaders.joined(separator: ", ")
                let stdInfo = standardLimits.map { "req=\($0.requestsRemaining)/\($0.requestsLimit) tok=\($0.tokensRemaining)/\($0.tokensLimit)" } ?? "nil"
                AppLogger.network.warning(
                    "No unified headers in \(http.statusCode) (model=\(model)). RL headers: \(found). Standard: \(stdInfo)"
                )

                if let fallback = await fetchClaudeCodeClientData(
                    accessToken: accessToken,
                    cached: cached,
                    accountId: accountId,
                    model: model,
                    callerStandardLimits: standardLimits
                ) {
                    return .success(fallback)
                }
            }

            let result = APIFetchResult(
                rateLimits: rateLimits,
                rateLimitSource: rateLimits == nil ? nil : .anthropicAPIHeaders,
                standardLimits: standardLimits,
                profile: profile ?? cached?.profile,
                hasStandardRateLimitHeaders: hasStandardRateLimitHeaders
            )
            return .success(result)
        } catch {
            return .networkError
        }
    }

    /// Claude Code now uses a separate OAuth-backed endpoint for client metadata
    /// and usage state. When the Messages API stops returning unified headers,
    /// fall back to that endpoint and parse either headers or a structured JSON body.
    private func fetchClaudeCodeClientData(
        accessToken: String,
        cached: APIFetchResult?,
        accountId: String,
        model: String,
        callerStandardLimits: StandardRateLimits? = nil
    ) async -> APIFetchResult? {
        var request = URLRequest(url: clientDataURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await SecureNetworking.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }

            AppLogger.network.info("client_data response: status=\(http.statusCode), bodySize=\(data.count)")
            if let bodyPreview = String(data: data.prefix(512), encoding: .utf8) {
                AppLogger.network.debug("client_data body preview: \(bodyPreview)")
            }

            if http.statusCode == 401 || http.statusCode == 403 { return nil }
            guard (200..<300).contains(http.statusCode) || http.statusCode == 429 else { return nil }

            let headerRL = RateLimitUsage.parse(headers: http.allHeaderFields)
            let bodyRL = RateLimitUsage.parse(clientData: data)
            let rateLimits = headerRL ?? bodyRL

            if rateLimits == nil {
                // Log top-level keys to help diagnose client_data format changes
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let keys = json.keys.sorted().joined(separator: ", ")
                    AppLogger.network.warning("client_data: no rate limits parsed. Top-level keys: [\(keys, privacy: .public)]")
                } else if let bodyStr = String(data: data.prefix(256), encoding: .utf8) {
                    AppLogger.network.warning("client_data: not a JSON object. Body: \(bodyStr, privacy: .public)")
                } else {
                    AppLogger.network.warning("client_data: response is not a JSON object")
                }
            }

            let profile = APIProfile.parse(headers: http.allHeaderFields)
                ?? APIProfile.parse(clientData: data)
                ?? cached?.profile
            let hasStandardRateLimitHeaders = Self.containsStandardRateLimitHeaders(http.allHeaderFields)
            guard rateLimits != nil || profile != nil || hasStandardRateLimitHeaders else { return nil }

            if rateLimits != nil {
                saveWorkingModel(model, accountId: accountId)
            }

            let normalizedRateLimits = rateLimits.map {
                http.statusCode == 429 ? $0.markedThrottled() : $0
            }

            return APIFetchResult(
                rateLimits: normalizedRateLimits,
                rateLimitSource: normalizedRateLimits == nil ? nil : .claudeCodeClientData,
                standardLimits: callerStandardLimits,
                profile: profile,
                hasStandardRateLimitHeaders: hasStandardRateLimitHeaders
            )
        } catch {
            return nil
        }
    }

    private static func containsStandardRateLimitHeaders(_ headers: [AnyHashable: Any]) -> Bool {
        headers.keys
            .compactMap { $0 as? String }
            .map { $0.lowercased() }
            .contains { key in
                key.hasPrefix("anthropic-ratelimit-") && !key.hasPrefix("anthropic-ratelimit-unified-")
            }
    }

    // MARK: - Rate limit persistence (survive app restart)

    /// Wrapper for persisting rate limits + fetch timestamp.
    private struct PersistedRateLimits: Codable {
        let rateLimits: RateLimitUsage?
        let rateLimitSource: RateLimitSource?
        let standardLimits: StandardRateLimits?
        let fetchedAt: Date
    }

    /// Save rate limits to UserDefaults for instant display on next launch.
    private func persistRateLimits(_ result: APIFetchResult, accountId: String) {
        guard result.rateLimits != nil || result.standardLimits != nil else { return }
        let key = Self.persistKeyPrefix + accountId
        let persisted = PersistedRateLimits(
            rateLimits: result.rateLimits,
            rateLimitSource: result.rateLimitSource,
            standardLimits: result.standardLimits,
            fetchedAt: result.fetchedAt
        )
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
                rateLimitSource: persisted.rateLimitSource,
                standardLimits: persisted.standardLimits,
                profile: nil,
                fetchedAt: persisted.fetchedAt,
                isCached: true
            )
        }
    }

}
