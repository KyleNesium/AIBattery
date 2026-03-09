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
