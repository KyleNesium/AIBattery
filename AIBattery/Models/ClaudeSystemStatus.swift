import Foundation

/// A status page component with its alert configuration.
struct StatusComponent {
    let id: String
    let name: String
    let alertKey: String
}

struct ClaudeSystemStatus {
    let indicator: StatusIndicator
    let description: String
    let incidentNames: [String]
    let statusPageURL: String
    /// Per-component statuses keyed by Statuspage component ID.
    var componentStatuses: [String: StatusIndicator] = [:]

    /// Convenience for single-incident access.
    var incidentName: String? { incidentNames.first }

    static let unknown = ClaudeSystemStatus(
        indicator: .unknown,
        description: "Status unavailable",
        incidentNames: [],
        statusPageURL: StatusChecker.statusPageBaseURL
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
