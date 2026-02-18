import Foundation
import os

/// Fetches Claude system status from the public Statuspage API.
/// Checks Claude API + Claude Code component status.
final class StatusChecker {
    static let shared = StatusChecker()

    private let summaryURL = URL(string: "https://status.claude.com/api/v2/summary.json")!

    /// Statuspage component IDs for services we track.
    static let claudeAPIComponentID = "k8w3r06qmzrp"
    static let claudeCodeComponentID = "yyzkbfz2thpt"

    private let relevantComponents: Set<String> = [
        claudeAPIComponentID,
        claudeCodeComponentID,
    ]

    private var cachedStatus: ClaudeSystemStatus?

    /// Backoff: when a fetch fails, don't retry for this many seconds.
    private static let backoffInterval: TimeInterval = 300 // 5 minutes
    private var lastFailedAt: Date?

    func fetchStatus() async -> ClaudeSystemStatus {
        // Skip fetch if we recently failed (backoff)
        if let failedAt = lastFailedAt,
           Date().timeIntervalSince(failedAt) < Self.backoffInterval {
            return cachedStatus ?? .unknown
        }

        var request = URLRequest(url: summaryURL)
        request.timeoutInterval = 5

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                lastFailedAt = Date()
                AppLogger.network.warning("StatusChecker HTTP error, backing off for 5 min")
                return cachedStatus ?? .unknown
            }

            let summary = try JSONDecoder().decode(StatusPageSummary.self, from: data)
            let result = parseStatus(summary)
            cachedStatus = result
            lastFailedAt = nil // Clear backoff on success
            return result
        } catch {
            lastFailedAt = Date()
            AppLogger.network.warning("StatusChecker fetch failed: \(error.localizedDescription, privacy: .public), backing off for 5 min")
            return cachedStatus ?? .unknown
        }
    }

    private func parseStatus(_ summary: StatusPageSummary) -> ClaudeSystemStatus {
        // Find the worst status among relevant components
        let components = summary.components.filter { relevantComponents.contains($0.id) }
        guard !components.isEmpty else {
            // Fallback to overall status
            return ClaudeSystemStatus(
                indicator: StatusIndicator.from(summary.status.indicator),
                description: summary.status.description,
                incidentName: nil,
                statusPageURL: "https://status.claude.com"
            )
        }

        guard let worstComponent = components.max(by: { a, b in
            StatusIndicator.from(a.status).severity < StatusIndicator.from(b.status).severity
        }) else {
            return .unknown
        }

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
            let affected = components.filter { StatusIndicator.from($0.status) != .operational }
            let names = affected.map(\.name).joined(separator: ", ")
            description = "\(names): \(worstComponent.status.replacingOccurrences(of: "_", with: " "))"
        }

        // Per-component statuses
        let apiStatus = components.first(where: { $0.id == Self.claudeAPIComponentID })
            .map { StatusIndicator.from($0.status) } ?? .unknown
        let codeStatus = components.first(where: { $0.id == Self.claudeCodeComponentID })
            .map { StatusIndicator.from($0.status) } ?? .unknown

        return ClaudeSystemStatus(
            indicator: worstIndicator,
            description: description,
            incidentName: activeIncident?.name,
            statusPageURL: "https://status.claude.com",
            claudeAPIStatus: apiStatus,
            claudeCodeStatus: codeStatus
        )
    }
}

// MARK: - Models

struct ClaudeSystemStatus {
    let indicator: StatusIndicator
    let description: String
    let incidentName: String?
    let statusPageURL: String
    /// Per-component status: Claude API (claude.ai) and Claude Code.
    var claudeAPIStatus: StatusIndicator = .unknown
    var claudeCodeStatus: StatusIndicator = .unknown

    static let unknown = ClaudeSystemStatus(
        indicator: .unknown,
        description: "Status unavailable",
        incidentName: nil,
        statusPageURL: "https://status.claude.com"
    )
}

enum StatusIndicator: String {
    case operational
    case degradedPerformance
    case partialOutage
    case majorOutage
    case maintenance
    case unknown

    var severity: Int {
        switch self {
        case .operational: return 0
        case .maintenance: return 1
        case .degradedPerformance: return 2
        case .partialOutage: return 3
        case .majorOutage: return 4
        case .unknown: return -1
        }
    }

    /// Human-readable display name for notifications and UI.
    var displayName: String {
        switch self {
        case .operational: return "operational"
        case .degradedPerformance: return "degraded performance"
        case .partialOutage: return "partial outage"
        case .majorOutage: return "major outage"
        case .maintenance: return "maintenance"
        case .unknown: return "unknown"
        }
    }

    static func from(_ string: String) -> StatusIndicator {
        switch string.lowercased() {
        case "none", "operational": return .operational
        case "minor", "degraded_performance", "elevated": return .degradedPerformance
        case "major", "partial_outage": return .partialOutage
        case "critical", "major_outage": return .majorOutage
        case "maintenance", "under_maintenance": return .maintenance
        default: return .unknown
        }
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
