import Foundation
import os

/// One provider's public Statuspage feed: where to fetch, where to link, which
/// components matter. Claude and OpenAI both run Atlassian Statuspage, so a single
/// parser serves both — only the config differs.
struct StatusFeedConfig: Sendable {
    let summaryURL: URL
    /// Base URL of the human-facing status page (footer link).
    let statusPageBaseURL: String
    /// Components the app alerts on (and, for a filtered feed, the only ones that
    /// drive the overall indicator).
    let knownComponents: [StatusComponent]
    /// nil → every component in the summary counts toward the worst indicator /
    /// description / incident escalation (Claude: the page IS the product).
    /// Non-nil → only these component IDs count. OpenAI's page lists 25+ unrelated
    /// products (Sora, Images, …) whose outages must not paint the Codex dot red.
    let componentFilter: Set<String>?

    /// status.claude.com — unchanged behaviour from before provider support.
    static let claude = StatusFeedConfig(
        summaryURL: URL(string: "https://status.claude.com/api/v2/summary.json")!,
        statusPageBaseURL: "https://status.claude.com",
        knownComponents: [
            StatusComponent(id: "rwppv331jlwc", name: "claude.ai", alertKey: "claudeAI"),
            StatusComponent(id: "0qbwn08sd68x", name: "Console", alertKey: "console"),
            StatusComponent(id: "k8w3r06qmzrp", name: "Claude API", alertKey: "claudeAPI"),
            StatusComponent(id: "yyzkbfz2thpt", name: "Claude Code", alertKey: "claudeCode"),
            StatusComponent(id: "0scnb50nvy53", name: "Claude for Gov", alertKey: "claudeForGov"),
        ],
        componentFilter: nil
    )
}

/// Fetches a provider's system status from its public Statuspage API and reduces it
/// to one indicator. One instance per feed (`shared` = Claude, `codex` = OpenAI),
/// each with its own cache and exponential backoff.
@MainActor
final class StatusChecker {
    static let shared = StatusChecker(config: .claude)
    static let codex = StatusChecker(config: .codex)

    static func shared(for provider: AIProvider) -> StatusChecker {
        switch provider {
        case .claude: shared
        case .codex: codex
        }
    }

    let config: StatusFeedConfig

    init(config: StatusFeedConfig) {
        self.config = config
    }

    /// Base URL for the Claude status page. Kept as a static for `ClaudeSystemStatus.unknown`
    /// and legacy call sites; provider-aware code reads `config.statusPageBaseURL`.
    nonisolated static let statusPageBaseURL = StatusFeedConfig.claude.statusPageBaseURL

    /// Claude components the app alerts on (legacy static; see `StatusFeedConfig.claude`).
    nonisolated static var knownComponents: [StatusComponent] { StatusFeedConfig.claude.knownComponents }

    nonisolated private static let jsonDecoder = JSONDecoder()
    private var cachedStatus: ClaudeSystemStatus?

    /// Exponential backoff with jitter for failed fetches — delegated to `RetryPolicy.statusCheck`
    /// (60s → 120s → 240s, capped at 5 min, ±20% jitter). Jitter prevents thundering herd
    /// on macOS wake from sleep.
    private var lastFailedAt: Date?
    private var failureCount = 0
    /// Stored backoff interval — computed once per failure, not re-randomized on every check.
    private var currentBackoff: TimeInterval = 0

    /// Compute and store the backoff interval for the current failure count.
    private func updateBackoff() {
        currentBackoff = RetryPolicy.statusCheck.delay(forAttempt: failureCount)
    }

    func fetchStatus() async -> ClaudeSystemStatus {
        // Skip fetch if we recently failed (exponential backoff)
        if let failedAt = lastFailedAt, failureCount > 0,
           Date().timeIntervalSince(failedAt) < currentBackoff {
            return cachedStatus ?? .unknown(statusPageURL: config.statusPageBaseURL)
        }

        // Hop off MainActor for the HTTP request, decode, and parse.
        // We re-enter MainActor only to mutate cache/backoff state.
        let outcome = await Self.fetchAndParse(config: config, timeout: 5)
        switch outcome {
        case let .success(status):
            cachedStatus = status
            failureCount = 0
            lastFailedAt = nil
            return status
        case let .httpError(code):
            failureCount += 1
            updateBackoff()
            lastFailedAt = Date()
            AppLogger.network.warning("StatusChecker(\(self.config.statusPageBaseURL, privacy: .public)) HTTP \(code), backing off \(Int(self.currentBackoff))s (attempt \(self.failureCount))")
            return cachedStatus ?? .unknown(statusPageURL: config.statusPageBaseURL)
        case let .failure(error):
            failureCount += 1
            updateBackoff()
            lastFailedAt = Date()
            AppLogger.network.warning("StatusChecker(\(self.config.statusPageBaseURL, privacy: .public)) fetch failed: \(error.localizedDescription, privacy: .public), backing off \(Int(self.currentBackoff))s (attempt \(self.failureCount))")
            return cachedStatus ?? .unknown(statusPageURL: config.statusPageBaseURL)
        }
    }

    /// Outcome of a single off-MainActor fetch attempt. Used to keep the
    /// async pipeline `nonisolated` while letting the `@MainActor` caller
    /// branch on what happened for logging + backoff bookkeeping.
    enum FetchOutcome {
        case success(ClaudeSystemStatus)
        case httpError(Int)
        case failure(Error)
    }

    /// Off-MainActor fetch + decode + parse. Pure: takes a feed config, returns an
    /// outcome. All instance state lives on MainActor; this never touches `self`.
    nonisolated static func fetchAndParse(config: StatusFeedConfig, timeout: TimeInterval) async -> FetchOutcome {
        var request = URLRequest(url: config.summaryURL)
        request.timeoutInterval = timeout
        do {
            let (data, response) = try await SecureNetworking.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .httpError(0)
            }
            guard http.statusCode == 200 else {
                return .httpError(http.statusCode)
            }
            let summary = try jsonDecoder.decode(StatusPageSummary.self, from: data)
            return .success(parseStatus(summary, config: config))
        } catch {
            return .failure(error)
        }
    }

    /// Pure parser — `nonisolated static` so tests exercise it off-MainActor and
    /// `fetchAndParse` calls it without an actor hop. With a `componentFilter`, only
    /// the filtered components (and incidents touching them) drive the result.
    nonisolated static func parseStatus(_ summary: StatusPageSummary, config: StatusFeedConfig) -> ClaudeSystemStatus {
        let components: [StatusPageComponent] = if let filter = config.componentFilter {
            summary.components.filter { filter.contains($0.id) }
        } else {
            summary.components
        }
        guard !components.isEmpty else {
            // Fallback to overall status — for a filtered feed whose components are all
            // missing from the summary we know nothing Codex-specific, so report unknown
            // rather than the whole page's (unrelated) indicator.
            if config.componentFilter != nil {
                return .unknown(statusPageURL: config.statusPageBaseURL)
            }
            return ClaudeSystemStatus(
                indicator: StatusIndicator.from(summary.status.indicator),
                description: summary.status.description,
                incidentNames: [],
                statusPageURL: config.statusPageBaseURL
            )
        }

        // Single pass: build per-component statuses, track worst component, collect affected names
        var componentStatuses: [String: StatusIndicator] = [:]
        var worstComponent: StatusPageComponent?
        var worstComponentSeverity = -1
        var affectedNames: [String] = []

        for component in components {
            let indicator = StatusIndicator.from(component.status)
            componentStatuses[component.id] = indicator
            if indicator.severity > worstComponentSeverity {
                worstComponent = component
                worstComponentSeverity = indicator.severity
            }
            if indicator != .operational {
                affectedNames.append(component.name)
            }
        }

        guard let worstComponent else { return .unknown }
        var worstIndicator = StatusIndicator.from(worstComponent.status)

        // Check for active incidents. With a component filter, an incident counts only
        // when it explicitly names a filtered component — one with no component list
        // could be about anything else on the page and must not colour this feed.
        let activeIncidents = summary.incidents.filter { incident in
            guard incident.status != "resolved", incident.status != "postmortem" else { return false }
            guard let filter = config.componentFilter else { return true }
            return incident.components?.contains { filter.contains($0.id) } ?? false
        }
        let activeIncident = activeIncidents.first

        // Factor in incident impact — components may still read "operational"
        // while an active incident is ongoing (Statuspage quirk).
        for incident in activeIncidents {
            let impactIndicator = StatusIndicator.from(incident.impact)
            if impactIndicator.severity > worstIndicator.severity {
                worstIndicator = impactIndicator
            }
        }

        // If there are active incidents but impact is "none", show at least degraded
        if worstIndicator == .operational && !activeIncidents.isEmpty {
            worstIndicator = .degradedPerformance
        }

        // Build description
        let description: String
        if worstIndicator == .operational {
            description = "All Systems Operational"
        } else if let incident = activeIncident {
            description = incident.name
        } else {
            let names = affectedNames.joined(separator: ", ")
            description = "\(names): \(worstComponent.status.replacingOccurrences(of: "_", with: " "))"
        }

        return ClaudeSystemStatus(
            indicator: worstIndicator,
            description: description,
            incidentNames: activeIncidents.map(\.name),
            statusPageURL: config.statusPageBaseURL,
            componentStatuses: componentStatuses
        )
    }
}

// MARK: - Statuspage JSON models (internal so tests can build summaries directly)

struct StatusPageSummary: Codable {
    let status: StatusPageStatus
    let components: [StatusPageComponent]
    let incidents: [StatusPageIncident]
}

struct StatusPageStatus: Codable {
    let indicator: String
    let description: String
}

struct StatusPageComponent: Codable {
    let id: String
    let name: String
    let status: String
}

struct StatusPageIncident: Codable {
    let id: String
    let name: String
    let status: String
    let impact: String
    /// Components the incident lists as affected (Statuspage includes these; optional
    /// because the app tolerates their absence).
    var components: [StatusPageComponent]? = nil
}
