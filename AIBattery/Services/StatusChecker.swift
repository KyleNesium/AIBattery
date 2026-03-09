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

    private static let jsonDecoder = JSONDecoder()
    private var cachedStatus: ClaudeSystemStatus?

    /// Exponential backoff with jitter for failed fetches.
    /// Base interval doubles on each failure (60s → 120s → 240s), capped at 5 min.
    /// Jitter (±20%) prevents thundering herd on macOS wake from sleep.
    private static let baseBackoff: TimeInterval = 60
    private static let maxBackoff: TimeInterval = 300
    private var lastFailedAt: Date?
    private var failureCount = 0
    /// Stored backoff interval — computed once per failure, not re-randomized on every check.
    private var currentBackoff: TimeInterval = 0

    /// Compute and store the backoff interval for the current failure count.
    private func updateBackoff() {
        let raw = Self.baseBackoff * pow(2, Double(failureCount - 1))
        let capped = min(raw, Self.maxBackoff)
        currentBackoff = capped * Double.random(in: 0.8...1.2)
    }

    func fetchStatus() async -> ClaudeSystemStatus {
        // Skip fetch if we recently failed (exponential backoff)
        if let failedAt = lastFailedAt, failureCount > 0,
           Date().timeIntervalSince(failedAt) < currentBackoff {
            return cachedStatus ?? .unknown
        }

        var request = URLRequest(url: summaryURL)
        request.timeoutInterval = 5

        do {
            let (data, response) = try await SecureNetworking.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                failureCount += 1
                updateBackoff()
                lastFailedAt = Date()
                AppLogger.network.warning("StatusChecker HTTP error, backing off \(Int(self.currentBackoff))s (attempt \(self.failureCount))")
                return cachedStatus ?? .unknown
            }

            let summary = try Self.jsonDecoder.decode(StatusPageSummary.self, from: data)
            let result = parseStatus(summary)
            cachedStatus = result
            failureCount = 0
            lastFailedAt = nil
            return result
        } catch {
            failureCount += 1
            updateBackoff()
            lastFailedAt = Date()
            AppLogger.network.warning("StatusChecker fetch failed: \(error.localizedDescription, privacy: .public), backing off \(Int(self.currentBackoff))s (attempt \(self.failureCount))")
            return cachedStatus ?? .unknown
        }
    }

    private func parseStatus(_ summary: StatusPageSummary) -> ClaudeSystemStatus {
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
