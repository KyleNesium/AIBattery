import Foundation
import os

/// Fetches Claude system status from the public Statuspage API.
/// Checks all known status page components.
@MainActor
final class StatusChecker {
    static let shared = StatusChecker()

    private let summaryURL = URL(string: "https://status.claude.com/api/v2/summary.json")!

    /// Base URL for the public status page.
    nonisolated static let statusPageBaseURL = "https://status.claude.com"

    /// All status page components the app can alert on.
    nonisolated static let knownComponents: [StatusComponent] = [
        StatusComponent(id: "rwppv331jlwc", name: "claude.ai", alertKey: "claudeAI"),
        StatusComponent(id: "0qbwn08sd68x", name: "Console", alertKey: "console"),
        StatusComponent(id: "k8w3r06qmzrp", name: "Claude API", alertKey: "claudeAPI"),
        StatusComponent(id: "yyzkbfz2thpt", name: "Claude Code", alertKey: "claudeCode"),
        StatusComponent(id: "0scnb50nvy53", name: "Claude for Gov", alertKey: "claudeForGov"),
    ]

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
            return cachedStatus ?? .unknown
        }

        // Hop off MainActor for the HTTP request, decode, and parse.
        // We re-enter MainActor only to mutate cache/backoff state.
        let outcome = await Self.fetchAndParse(url: summaryURL, timeout: 5)
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
            AppLogger.network.warning("StatusChecker HTTP \(code), backing off \(Int(self.currentBackoff))s (attempt \(self.failureCount))")
            return cachedStatus ?? .unknown
        case let .failure(error):
            failureCount += 1
            updateBackoff()
            lastFailedAt = Date()
            AppLogger.network.warning("StatusChecker fetch failed: \(error.localizedDescription, privacy: .public), backing off \(Int(self.currentBackoff))s (attempt \(self.failureCount))")
            return cachedStatus ?? .unknown
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

    /// Off-MainActor fetch + decode + parse. Pure: takes a URL, returns an outcome.
    /// All instance state lives on MainActor; this function never touches `self`.
    nonisolated static func fetchAndParse(url: URL, timeout: TimeInterval) async -> FetchOutcome {
        var request = URLRequest(url: url)
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
            return .success(parseStatus(summary))
        } catch {
            return .failure(error)
        }
    }

    /// Pure parser — exposed as `nonisolated static` so tests can exercise it
    /// off-MainActor and `fetchAndParse` can call it without an actor hop.
    /// Filescope visibility because `StatusPageSummary` is fileprivate.
    nonisolated fileprivate static func parseStatus(_ summary: StatusPageSummary) -> ClaudeSystemStatus {
        let components = summary.components
        guard !components.isEmpty else {
            // Fallback to overall status
            return ClaudeSystemStatus(
                indicator: StatusIndicator.from(summary.status.indicator),
                description: summary.status.description,
                incidentNames: [],
                statusPageURL: StatusChecker.statusPageBaseURL
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

        // Check for active incidents
        let activeIncidents = summary.incidents.filter { incident in
            incident.status != "resolved" && incident.status != "postmortem"
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
            statusPageURL: StatusChecker.statusPageBaseURL,
            componentStatuses: componentStatuses
        )
    }
}

// MARK: - Statuspage JSON models

private struct StatusPageSummary: Codable {
    let status: StatusPageStatus
    let components: [StatusPageComponent]
    let incidents: [StatusPageIncident]
}

private struct StatusPageStatus: Codable {
    let indicator: String
    let description: String
}

private struct StatusPageComponent: Codable {
    let id: String
    let name: String
    let status: String
}

private struct StatusPageIncident: Codable {
    let id: String
    let name: String
    let status: String
    let impact: String
}
