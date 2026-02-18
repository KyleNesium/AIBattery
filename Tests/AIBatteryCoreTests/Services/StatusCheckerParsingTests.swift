import Testing
@testable import AIBatteryCore

@Suite("StatusChecker — incident escalation")
struct StatusCheckerParsingTests {

    // MARK: - Incident impact parsing

    /// "none" impact should map to operational via StatusIndicator.from().
    @Test func impactNone_mapsToOperational() {
        #expect(StatusIndicator.from("none") == .operational)
    }

    /// "minor" impact should map to degradedPerformance.
    @Test func impactMinor_mapsToDegraded() {
        #expect(StatusIndicator.from("minor") == .degradedPerformance)
    }

    /// "major" impact should map to partialOutage.
    @Test func impactMajor_mapsToPartialOutage() {
        #expect(StatusIndicator.from("major") == .partialOutage)
    }

    /// "critical" impact should map to majorOutage.
    @Test func impactCritical_mapsToMajorOutage() {
        #expect(StatusIndicator.from("critical") == .majorOutage)
    }

    // MARK: - Severity ordering for escalation

    /// degradedPerformance severity must be higher than operational
    /// so that "minor" incident impact can escalate an "operational" component.
    @Test func degradedSeverity_exceedsOperational() {
        #expect(StatusIndicator.degradedPerformance.severity > StatusIndicator.operational.severity)
    }

    /// Verify the full severity chain:
    /// unknown < operational < maintenance < degraded < partial < major
    @Test func fullSeverityChain() {
        let ordered: [StatusIndicator] = [
            .unknown, .operational, .maintenance,
            .degradedPerformance, .partialOutage, .majorOutage,
        ]
        for i in 0..<(ordered.count - 1) {
            #expect(
                ordered[i].severity < ordered[i + 1].severity,
                "\(ordered[i]).severity should be less than \(ordered[i + 1]).severity"
            )
        }
    }

    // MARK: - Component ID constants

    @Test func componentIDs_areNonEmpty() {
        #expect(!StatusChecker.claudeAPIComponentID.isEmpty)
        #expect(!StatusChecker.claudeCodeComponentID.isEmpty)
    }

    @Test func componentIDs_areDistinct() {
        #expect(StatusChecker.claudeAPIComponentID != StatusChecker.claudeCodeComponentID)
    }
}
