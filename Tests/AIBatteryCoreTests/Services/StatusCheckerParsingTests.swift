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

    // MARK: - Extended incident escalation

    @Test func degradedSeverity_exceedsMaintenance() {
        #expect(StatusIndicator.degradedPerformance.severity > StatusIndicator.maintenance.severity)
    }

    @Test func majorOutage_isHighestSeverity() {
        let all: [StatusIndicator] = [.unknown, .operational, .maintenance, .degradedPerformance, .partialOutage]
        for indicator in all {
            #expect(StatusIndicator.majorOutage.severity > indicator.severity,
                    "majorOutage should exceed \(indicator)")
        }
    }

    // MARK: - Component ID format

    @Test func componentIDs_areAlphanumeric() {
        let alphanumeric = CharacterSet.alphanumerics
        #expect(StatusChecker.claudeAPIComponentID.unicodeScalars.allSatisfy { alphanumeric.contains($0) })
        #expect(StatusChecker.claudeCodeComponentID.unicodeScalars.allSatisfy { alphanumeric.contains($0) })
    }

    // MARK: - Display names

    @Test func allIndicators_haveNonEmptyDisplayNames() {
        let indicators: [StatusIndicator] = [
            .operational, .degradedPerformance, .partialOutage,
            .majorOutage, .maintenance, .unknown,
        ]
        for indicator in indicators {
            #expect(!indicator.displayName.isEmpty, "\(indicator) has empty displayName")
        }
    }
}
