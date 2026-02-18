import Testing
@testable import AIBatteryCore

@Suite("StatusIndicator")
struct StatusIndicatorTests {

    // MARK: - from() parsing

    @Test func from_operational() {
        #expect(StatusIndicator.from("operational") == .operational)
        #expect(StatusIndicator.from("none") == .operational)
    }

    @Test func from_degradedPerformance() {
        #expect(StatusIndicator.from("degraded_performance") == .degradedPerformance)
        #expect(StatusIndicator.from("minor") == .degradedPerformance)
        // Statuspage API returns "elevated" for elevated error rates
        #expect(StatusIndicator.from("elevated") == .degradedPerformance)
    }

    @Test func from_partialOutage() {
        #expect(StatusIndicator.from("partial_outage") == .partialOutage)
        #expect(StatusIndicator.from("major") == .partialOutage)
    }

    @Test func from_majorOutage() {
        #expect(StatusIndicator.from("major_outage") == .majorOutage)
        #expect(StatusIndicator.from("critical") == .majorOutage)
    }

    @Test func from_maintenance() {
        #expect(StatusIndicator.from("maintenance") == .maintenance)
        #expect(StatusIndicator.from("under_maintenance") == .maintenance)
    }

    @Test func from_unknown() {
        #expect(StatusIndicator.from("unknown_status") == .unknown)
        #expect(StatusIndicator.from("") == .unknown)
        #expect(StatusIndicator.from("foo") == .unknown)
    }

    @Test func from_caseInsensitive() {
        #expect(StatusIndicator.from("OPERATIONAL") == .operational)
        #expect(StatusIndicator.from("Degraded_Performance") == .degradedPerformance)
    }

    // MARK: - Severity ordering

    @Test func severity_ordering() {
        #expect(StatusIndicator.unknown.severity < StatusIndicator.operational.severity)
        #expect(StatusIndicator.operational.severity < StatusIndicator.maintenance.severity)
        #expect(StatusIndicator.maintenance.severity < StatusIndicator.degradedPerformance.severity)
        #expect(StatusIndicator.degradedPerformance.severity < StatusIndicator.partialOutage.severity)
        #expect(StatusIndicator.partialOutage.severity < StatusIndicator.majorOutage.severity)
    }

    // MARK: - Display name

    @Test func displayName() {
        #expect(StatusIndicator.operational.displayName == "operational")
        #expect(StatusIndicator.degradedPerformance.displayName == "degraded performance")
        #expect(StatusIndicator.partialOutage.displayName == "partial outage")
        #expect(StatusIndicator.majorOutage.displayName == "major outage")
        #expect(StatusIndicator.maintenance.displayName == "maintenance")
        #expect(StatusIndicator.unknown.displayName == "unknown")
    }
}
