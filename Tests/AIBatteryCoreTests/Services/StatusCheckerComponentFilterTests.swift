import Foundation
import Testing
@testable import AIBatteryCore

/// Pins the feed-configurable parser: the OpenAI status page lists 25+ unrelated
/// products, so the Codex feed must only react to Codex components. The Claude feed
/// (filter nil) must behave exactly as before.
@Suite("StatusChecker — feed config + component filter")
struct StatusCheckerComponentFilterTests {
    private let codexAPI = StatusPageComponent(id: "codex-api", name: "Codex API", status: "operational")
    private let sora = StatusPageComponent(id: "sora", name: "Sora", status: "major_outage")

    private func config(filter: Set<String>?) -> StatusFeedConfig {
        StatusFeedConfig(
            summaryURL: URL(string: "https://example.invalid/summary.json")!,
            statusPageBaseURL: "https://status.example.invalid",
            knownComponents: [StatusComponent(id: "codex-api", name: "Codex API", alertKey: "codexAPI")],
            componentFilter: filter
        )
    }

    private func summary(components: [StatusPageComponent], incidents: [StatusPageIncident] = []) -> StatusPageSummary {
        StatusPageSummary(
            status: StatusPageStatus(indicator: "major", description: "Partial System Outage"),
            components: components,
            incidents: incidents
        )
    }

    @Test func filter_ignoresUnrelatedComponentOutage() {
        let status = StatusChecker.parseStatus(summary(components: [codexAPI, sora]), config: config(filter: ["codex-api"]))
        #expect(status.indicator == .operational)
        #expect(status.description == "All Systems Operational")
        #expect(status.componentStatuses["sora"] == nil)
        #expect(status.componentStatuses["codex-api"] == .operational)
    }

    @Test func filter_flagsFilteredComponentOutage() {
        let down = StatusPageComponent(id: "codex-api", name: "Codex API", status: "partial_outage")
        let status = StatusChecker.parseStatus(summary(components: [down, sora]), config: config(filter: ["codex-api"]))
        #expect(status.indicator == .partialOutage)
        #expect(status.description == "Codex API: partial outage")
    }

    @Test func noFilter_considersEveryComponent() {
        let status = StatusChecker.parseStatus(summary(components: [codexAPI, sora]), config: config(filter: nil))
        #expect(status.indicator == .majorOutage)
        #expect(status.componentStatuses["sora"] == .majorOutage)
    }

    @Test func filter_incidentOnUnfilteredComponent_isIgnored() {
        let incident = StatusPageIncident(id: "i1", name: "Sora degraded", status: "investigating", impact: "minor", components: [sora])
        let status = StatusChecker.parseStatus(summary(components: [codexAPI, sora], incidents: [incident]), config: config(filter: ["codex-api"]))
        #expect(status.indicator == .operational)
        #expect(status.incidentNames.isEmpty)
    }

    @Test func filter_incidentOnFilteredComponent_escalates() {
        let incident = StatusPageIncident(id: "i2", name: "Codex API errors", status: "investigating", impact: "minor", components: [codexAPI])
        let status = StatusChecker.parseStatus(summary(components: [codexAPI, sora], incidents: [incident]), config: config(filter: ["codex-api"]))
        #expect(status.indicator == .degradedPerformance)
        #expect(status.incidentNames == ["Codex API errors"])
    }

    @Test func filter_incidentWithoutComponentList_stillCounts() {
        let incident = StatusPageIncident(id: "i3", name: "Elevated errors", status: "identified", impact: "minor", components: nil)
        let status = StatusChecker.parseStatus(summary(components: [codexAPI], incidents: [incident]), config: config(filter: ["codex-api"]))
        #expect(status.indicator == .degradedPerformance)
    }

    @Test func statusPageURL_propagatesFromConfig() {
        let status = StatusChecker.parseStatus(summary(components: [codexAPI]), config: config(filter: nil))
        #expect(status.statusPageURL == "https://status.example.invalid")
        #expect(ClaudeSystemStatus.unknown(statusPageURL: "https://x.invalid").statusPageURL == "https://x.invalid")
    }

    @Test func claudeConfig_matchesLegacyStatics() {
        #expect(StatusFeedConfig.claude.componentFilter == nil)
        #expect(StatusFeedConfig.claude.statusPageBaseURL == StatusChecker.statusPageBaseURL)
        #expect(StatusFeedConfig.claude.knownComponents.map(\.id) == StatusChecker.knownComponents.map(\.id))
        #expect(StatusFeedConfig.claude.summaryURL.absoluteString == "https://status.claude.com/api/v2/summary.json")
    }

    @Test @MainActor func sharedForProvider_routesToDistinctCheckers() {
        #expect(StatusChecker.shared(for: .claude) === StatusChecker.shared)
        #expect(StatusChecker.shared(for: .codex) === StatusChecker.codex)
        #expect(StatusChecker.codex.config.statusPageBaseURL == "https://status.openai.com")
    }
}
