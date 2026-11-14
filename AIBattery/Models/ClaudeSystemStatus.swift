import Foundation

/// A status page component with its alert configuration.
struct StatusComponent {
    let id: String
    let name: String
    let alertKey: String
}

/// Equatable so the ViewModel can skip republishing an unchanged status. The status
/// endpoint is polled every cycle and almost always returns the same thing; without the
/// comparison each poll re-rendered the open popover.
struct ClaudeSystemStatus: Equatable {
    let indicator: StatusIndicator
    let description: String
    let incidentNames: [String]
    let statusPageURL: String
    /// Per-component statuses keyed by Statuspage component ID.
    var componentStatuses: [String: StatusIndicator] = [:]
    /// Components on the same status page that this feed does not watch and that are
    /// degraded or down. Only a filtered feed fills it: for Codex, the rest of
    /// status.openai.com. They never colour the dot; the tooltip names them.
    var otherAffectedServices: [String] = []

    /// Convenience for single-incident access.
    var incidentName: String? { incidentNames.first }

    static let unknown = ClaudeSystemStatus(
        indicator: .unknown,
        description: "Status unavailable",
        incidentNames: [],
        statusPageURL: StatusChecker.statusPageBaseURL
    )

    /// Unknown status that still links to the right provider's status page.
    static func unknown(statusPageURL: String) -> ClaudeSystemStatus {
        ClaudeSystemStatus(indicator: .unknown, description: "Status unavailable", incidentNames: [], statusPageURL: statusPageURL)
    }
}

enum StatusIndicator: String, Equatable {
    case operational
    case degradedPerformance
    case partialOutage
    case majorOutage
    case maintenance
    case unknown

    var severity: Int {
        switch self {
        case .operational: 0
        case .maintenance: 1
        case .degradedPerformance: 2
        case .partialOutage: 3
        case .majorOutage: 4
        case .unknown: -1
        }
    }

    /// Human-readable display name for notifications and UI.
    var displayName: String {
        switch self {
        case .operational: "operational"
        case .degradedPerformance: "degraded performance"
        case .partialOutage: "partial outage"
        case .majorOutage: "major outage"
        case .maintenance: "maintenance"
        case .unknown: "unknown"
        }
    }

    static func from(_ string: String) -> StatusIndicator {
        switch string.lowercased() {
        case "none", "operational": .operational
        case "minor", "degraded_performance", "elevated": .degradedPerformance
        case "major", "partial_outage": .partialOutage
        case "critical", "major_outage": .majorOutage
        case "maintenance", "under_maintenance": .maintenance
        default: .unknown
        }
    }
}
