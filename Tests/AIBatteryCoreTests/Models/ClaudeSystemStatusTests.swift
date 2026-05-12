import Testing
import Foundation
@testable import AIBatteryCore

@Suite("ClaudeSystemStatus")
struct ClaudeSystemStatusTests {
    // MARK: - StatusIndicator.from()

    @Test func from_operational() {
        #expect(StatusIndicator.from("operational") == .operational)
        #expect(StatusIndicator.from("none") == .operational)
        #expect(StatusIndicator.from("Operational") == .operational)
        #expect(StatusIndicator.from("NONE") == .operational)
    }

    @Test func from_degradedPerformance() {
        #expect(StatusIndicator.from("minor") == .degradedPerformance)
        #expect(StatusIndicator.from("degraded_performance") == .degradedPerformance)
        #expect(StatusIndicator.from("elevated") == .degradedPerformance)
        #expect(StatusIndicator.from("MINOR") == .degradedPerformance)
    }

    @Test func from_partialOutage() {
        #expect(StatusIndicator.from("major") == .partialOutage)
        #expect(StatusIndicator.from("partial_outage") == .partialOutage)
    }

    @Test func from_majorOutage() {
        #expect(StatusIndicator.from("critical") == .majorOutage)
        #expect(StatusIndicator.from("major_outage") == .majorOutage)
    }

    @Test func from_maintenance() {
        #expect(StatusIndicator.from("maintenance") == .maintenance)
        #expect(StatusIndicator.from("under_maintenance") == .maintenance)
    }

    @Test func from_unknown() {
        #expect(StatusIndicator.from("") == .unknown)
        #expect(StatusIndicator.from("garbage") == .unknown)
        #expect(StatusIndicator.from("partly_cloudy") == .unknown)
    }

    // MARK: - Severity ordering

    @Test func severity_ordering() {
        #expect(StatusIndicator.operational.severity < StatusIndicator.maintenance.severity)
        #expect(StatusIndicator.maintenance.severity < StatusIndicator.degradedPerformance.severity)
        #expect(StatusIndicator.degradedPerformance.severity < StatusIndicator.partialOutage.severity)
        #expect(StatusIndicator.partialOutage.severity < StatusIndicator.majorOutage.severity)
        #expect(StatusIndicator.unknown.severity < StatusIndicator.operational.severity)
    }

    // MARK: - Display names

    @Test func displayName_allCases() {
        #expect(StatusIndicator.operational.displayName == "operational")
        #expect(StatusIndicator.degradedPerformance.displayName == "degraded performance")
        #expect(StatusIndicator.partialOutage.displayName == "partial outage")
        #expect(StatusIndicator.majorOutage.displayName == "major outage")
        #expect(StatusIndicator.maintenance.displayName == "maintenance")
        #expect(StatusIndicator.unknown.displayName == "unknown")
    }

    // MARK: - ClaudeSystemStatus convenience

    @Test func incidentName_returnsFirst() {
        let status = ClaudeSystemStatus(
            indicator: .partialOutage,
            description: "issues",
            incidentNames: ["API Down", "Dashboard Slow"],
            statusPageURL: "https://example.com"
        )
        #expect(status.incidentName == "API Down")
    }

    @Test func incidentName_nilWhenEmpty() {
        let status = ClaudeSystemStatus(
            indicator: .operational,
            description: "all good",
            incidentNames: [],
            statusPageURL: "https://example.com"
        )
        #expect(status.incidentName == nil)
    }

    @Test func unknown_hasDefaultValues() {
        let unknown = ClaudeSystemStatus.unknown
        #expect(unknown.indicator == .unknown)
        #expect(unknown.incidentNames.isEmpty)
        #expect(unknown.componentStatuses.isEmpty)
    }
}
