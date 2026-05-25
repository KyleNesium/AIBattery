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

    // URL constants are internal so the endpoint extensions
    // (RateLimitFetcher+UsageEndpoint.swift / +ClientData.swift) can use them.
    let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    let messagesURL = URL(string: "https://api.anthropic.com/v1/messages?beta=true")!
    let clientDataURL = URL(string: "https://api.anthropic.com/api/oauth/claude_cli/client_data")!
    /// Per-account cache of API results. Never expires — stale data is better than empty bars.
    /// Fresh fetches replace cached data on success.
    /// Read/written by the persistence extension (`RateLimitFetcher+Persistence.swift`).
    var cachedResults: [String: APIFetchResult] = [:]

    /// UserDefaults key prefix for persisted rate limits.
    /// Used by the persistence extension.
    static let persistKeyPrefix = "aibattery_rateLimits_"

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

    /// Per-account count of consecutive 401/403 responses from the Messages API.
    /// Reset on any non-auth-failure result. At or above `authErrorThreshold`,
    /// surface `authError = true` on returned APIFetchResults so the UI can
    /// prompt the user to reconnect instead of silently showing cached data.
    private var consecutiveAuthFailures: [String: Int] = [:]
    static let authErrorThreshold = 3

    init() {
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

    func saveWorkingModel(_ model: String, accountId: String) {
        lastWorkingModel[accountId] = model
        UserDefaults.standard.set(model, forKey: Self.workingModelKeyPrefix + accountId)
    }

    /// User-Agent string built from bundle version at startup.
    /// Internal so endpoint extension files can include it in requests.
    let userAgent: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        return "AIBattery/\(version) (macOS)"
    }()

    /// The model the user is actively running in Claude Code (from latest JSONL entry).
    /// Set by UsageAggregator after reading session logs.
    var activeUserModel: String?

    /// Fetches rate limits + org profile for a specific account.
    /// Primary: dedicated `/api/oauth/usage` endpoint (structured JSON, always returns data).
    /// Fallback: Messages API probe with unified headers (intermittent, ~10% hit rate).
    ///
    /// Actor isolation note: This method is `@MainActor`-isolated (the whole class is) but
    /// every `await SecureNetworking.data(for:)` call inside (and inside `tryFetch`,
    /// `fetchUsageEndpoint`, `fetchClaudeCodeClientData`) releases MainActor during the
    /// network suspension — `SecureNetworking.data` is `nonisolated`. So a 30s URLSession
    /// timeout does not freeze the UI; MainActor work runs in parallel. The suspension
    /// boundaries are the safety net.
    ///
    /// What does run on MainActor in this method:
    /// - Reading/writing `cachedResults`, `lastWorkingModel`, `consecutiveAuthFailures`
    /// - Calling `saveWorkingModel`, `buildHeaderResult`, `persistRateLimits`
    /// - Header parsing (`RateLimitUsage.parse`, `APIProfile.parse`, etc.) — these are
    ///   pure, sub-millisecond, and don't materially affect responsiveness.
    func fetch(accessToken: String, accountId: String) async -> APIFetchResult {
        // Primary: dedicated usage endpoint — no model probe needed, always returns data.
        if let usageResult = await fetchUsageEndpoint(accessToken: accessToken, accountId: accountId) {
            cachedResults[accountId] = usageResult
            persistRateLimits(usageResult, accountId: accountId)
            return usageResult
        }

        // Fallback: Messages API probe with unified headers.
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
                consecutiveAuthFailures[accountId] = 0
                cachedResults[accountId] = fetchResult
                persistRateLimits(fetchResult, accountId: accountId)
                return fetchResult
            case .modelUnavailable:
                continue
            case .authFailed:
                let count = (consecutiveAuthFailures[accountId] ?? 0) + 1
                consecutiveAuthFailures[accountId] = count
                let surfaceAuthError = count >= Self.authErrorThreshold
                if surfaceAuthError {
                    AppLogger.network.error("Messages API auth failed \(count) consecutive times for account \(accountId, privacy: .public) — surfacing authError to UI")
                }
                return cachedOrEmpty(accountId: accountId, authError: surfaceAuthError)
            case .networkError:
                // Network errors don't reset auth-failure count — a flaky network
                // shouldn't mask a persistent auth problem, but it shouldn't
                // count as one either.
                return cachedOrEmpty(accountId: accountId)
            }
        }

        return cachedOrEmpty(accountId: accountId)
    }

    /// Return cached result marked as stale, or an empty result.
    /// Always returns cached data when available — stale rate limits are better
    /// than empty bars (e.g., after waking from long sleep with expired token).
    /// Fresh fetches replace the cache naturally on success.
    ///
    /// Cached `rateLimits` are normalized with `withClearedExpiredWindows()` before
    /// being returned so a stale "throttled"/100% state doesn't outlive its window —
    /// e.g. a cache hit on wake from sleep after the 5h or 7d reset has already passed
    /// would otherwise display as still-depleted until a fresh fetch lands.
    func cachedOrEmpty(accountId: String, authError: Bool = false) -> APIFetchResult {
        if let cached = cachedResults[accountId] {
            return APIFetchResult(
                rateLimits: cached.rateLimits?.withClearedExpiredWindows(),
                rateLimitSource: cached.rateLimitSource,
                standardLimits: cached.standardLimits,
                profile: cached.profile,
                hasStandardRateLimitHeaders: cached.hasStandardRateLimitHeaders,
                fetchedAt: cached.fetchedAt,
                isCached: true,
                authError: authError
            )
        }
        return APIFetchResult(rateLimits: nil, profile: nil, authError: authError)
    }

    /// Inject a cached result for testing.
    func setCachedResult(_ result: APIFetchResult, for accountId: String) {
        cachedResults[accountId] = result
    }

    /// Parse a Retry-After header value into a delay in seconds.
    /// Returns nil if the value is missing, non-numeric, zero, or negative.
    /// Caps at `maxDelay` to prevent unbounded waits.
    ///
    /// Thin wrapper around `RetryPolicy.delay(retryAfterHeader:)`. Kept for
    /// callers that need a custom cap; pass-through to `RetryPolicy.rateLimit`
    /// when the default 30s cap is acceptable.
    nonisolated static func parseRetryAfter(_ value: String?, maxDelay: Double = 30) -> Double? {
        RetryPolicy(baseDelay: 1, maxDelay: maxDelay, multiplier: 2)
            .delay(retryAfterHeader: value)
    }

    /// Threshold above which a 429 with header-reported "allowed" status is still
    /// treated as a quota throttle (covers the rare case of header lag near the cap).
    nonisolated static let quotaExhaustionThreshold: Double = 0.95

    /// Whether an HTTP 429 should be treated as the user's 5h/7d quota throttle.
    ///
    /// A 429 alone is not enough — Anthropic returns 429 for several reasons:
    ///   - The user's 5h/7d quota is exhausted (the case we want to surface)
    ///   - Per-minute API rate limits
    ///   - IP/org-level restrictions or upstream incidents
    ///
    /// Trust the parsed headers: if they explicitly say "throttled", it's a quota
    /// throttle; if they say "allowed" with low utilization, the 429 is from another
    /// source and we must not pretend the user hit their quota.
    nonisolated static func quotaThrottleLikely(_ rl: RateLimitUsage) -> Bool {
        if rl.isThrottled { return true }
        let bindingUtilization = rl.representativeClaim == RateLimitUsage.sevenDayWindow
            ? rl.sevenDayUtilization
            : rl.fiveHourUtilization
        return bindingUtilization >= quotaExhaustionThreshold
    }

    private enum FetchResult {
        case success(APIFetchResult)
        case modelUnavailable
        case authFailed
        case networkError
    }

    /// Build an APIFetchResult from parsed rate limit headers.
    /// Saves the working model and constructs the result with `.anthropicAPIHeaders` source.
    private func buildHeaderResult(
        rateLimits: RateLimitUsage,
        headers: [AnyHashable: Any],
        cached: APIFetchResult?,
        model: String,
        accountId: String,
        standardLimits: StandardRateLimits?,
        markThrottled: Bool = false
    ) -> APIFetchResult {
        let profile = APIProfile.parse(headers: headers)
        saveWorkingModel(model, accountId: accountId)
        return APIFetchResult(
            rateLimits: markThrottled ? rateLimits.markedThrottled() : rateLimits,
            rateLimitSource: .anthropicAPIHeaders,
            standardLimits: standardLimits,
            profile: profile ?? cached?.profile,
            hasStandardRateLimitHeaders: Self.containsStandardRateLimitHeaders(headers)
        )
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
            "max_tokens": 1,
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
                    let quotaLikely = Self.quotaThrottleLikely(rateLimits)
                    if !quotaLikely {
                        AppLogger.network.warning("HTTP 429 received but headers indicate quota allowed (binding util=\(rateLimits.representativeClaim == RateLimitUsage.sevenDayWindow ? rateLimits.sevenDayUtilization : rateLimits.fiveHourUtilization)) — treating as upstream/per-minute throttle, not displaying as quota throttle")
                    }
                    return .success(buildHeaderResult(
                        rateLimits: rateLimits, headers: http.allHeaderFields,
                        cached: cached, model: model, accountId: accountId,
                        standardLimits: standardLimits, markThrottled: quotaLikely
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

                // 429 without unified headers — the user hit a rate limit.
                // Signal for auto-calibration: the current local token count ≈ the real limit.
                AppLogger.network.warning("429 without rate limit headers (model=\(model))")
                await MainActor.run { LocalUsageEstimate.calibrateFrom429() }

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
                            let retryQuotaLikely = retryHttp.statusCode == 429
                                && Self.quotaThrottleLikely(retryRL)
                            return .success(buildHeaderResult(
                                rateLimits: retryRL, headers: retryHttp.allHeaderFields,
                                cached: cached, model: model, accountId: accountId,
                                standardLimits: retryStdLimits, markThrottled: retryQuotaLikely
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
                    return .success(buildHeaderResult(
                        rateLimits: rateLimits, headers: http.allHeaderFields,
                        cached: cached, model: model, accountId: accountId,
                        standardLimits: standardLimits
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

    // The dedicated `/api/oauth/usage` endpoint (primary path) and its pure
    // interpreter live in `RateLimitFetcher+UsageEndpoint.swift`.

    // The Claude Code client-data fallback endpoint and its pure interpreter
    // (`interpretClaudeCodeClientData`, `fetchClaudeCodeClientData`,
    // `containsStandardRateLimitHeaders`) live in
    // `RateLimitFetcher+ClientData.swift`.

    // Persistence (`persistRateLimits`, `restorePersistedRateLimits`,
    // `PersistedRateLimits`) lives in `RateLimitFetcher+Persistence.swift`.
}
