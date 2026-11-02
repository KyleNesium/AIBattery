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

    @Test func filter_incidentWithoutComponentList_isIgnored() {
        // Spec §5: incidents count only when they name a Codex component. An incident
        // with no component list could be about anything on OpenAI's page.
        let incident = StatusPageIncident(id: "i3", name: "Elevated errors", status: "identified", impact: "minor", components: nil)
        let status = StatusChecker.parseStatus(summary(components: [codexAPI], incidents: [incident]), config: config(filter: ["codex-api"]))
        #expect(status.indicator == .operational)
        #expect(status.incidentNames.isEmpty)
    }

    @Test func noFilter_incidentWithoutComponentList_stillCounts() {
        let incident = StatusPageIncident(id: "i3", name: "Elevated errors", status: "identified", impact: "minor", components: nil)
        let status = StatusChecker.parseStatus(summary(components: [codexAPI], incidents: [incident]), config: config(filter: nil))
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

    // MARK: - Decoding a page that does not model incidents

    /// `status.openai.com` is Statuspage-shaped but is not Atlassian Statuspage: it omits
    /// `incidents` and `scheduled_maintenances` **entirely** rather than sending empty
    /// arrays. While `incidents` was decoded as required, every Codex status poll threw
    /// `keyNotFound` and backed off to the 5-minute cap, so the feed never once produced
    /// a reading — no dot, no outage notification. This payload is trimmed from the live
    /// response (2026-11-02), keys and nesting intact.
    @Test func decode_openAIShapedSummaryWithNoIncidentsKey() throws {
        let json = Data("""
        {
          "page": {
            "id": "01JMDK9XYNY6RXSED6SDWW50WY",
            "name": "OpenAI",
            "url": "https://status.openai.com/",
            "updated_at": "2026-10-16T20:01:40Z"
          },
          "status": { "description": "All Systems Operational", "indicator": "none" },
          "components": [
            { "id": "01KMKFAMWKQ81YWSE1Z18R6VHR", "name": "Codex in ChatGPT Desktop", "status": "operational" },
            { "id": "01JMDK9XYQ8R4MSFW8FM3RTBSS", "name": "Images", "status": "operational" }
          ]
        }
        """.utf8)

        let summary = try JSONDecoder().decode(StatusPageSummary.self, from: json)

        #expect(summary.incidents.isEmpty)
        #expect(summary.components.count == 2)
        #expect(summary.status.indicator == "none")
    }

    /// The Claude feed does send `incidents`, and that must still decode into the array
    /// the parser reads — the tolerance above is a default, not a discard.
    @Test func decode_statuspageSummaryKeepsItsIncidents() throws {
        let json = Data("""
        {
          "status": { "description": "Partial System Outage", "indicator": "major" },
          "components": [{ "id": "c1", "name": "API", "status": "partial_outage" }],
          "incidents": [
            { "id": "i1", "name": "Elevated error rates", "status": "identified", "impact": "major" }
          ]
        }
        """.utf8)

        let summary = try JSONDecoder().decode(StatusPageSummary.self, from: json)

        #expect(summary.incidents.map(\.id) == ["i1"])
        #expect(summary.incidents.first?.impact == "major")
    }

    /// With the decode fixed, the live page's single surviving Codex component is what
    /// the filter matches — the other four configured ids were removed when the page was
    /// reorganised, and a vanished id must drop out of the filter rather than break it.
    @Test func codexFilter_toleratesComponentsThatLeftThePage() {
        let live = StatusPageComponent(
            id: "01KMKFAMWKQ81YWSE1Z18R6VHR", name: "Codex in ChatGPT Desktop", status: "partial_outage"
        )
        let status = StatusChecker.parseStatus(
            summary(components: [live, sora]), config: StatusFeedConfig.codex
        )

        #expect(status.indicator == .partialOutage)
        #expect(status.componentStatuses["01KMKFAMWKQ81YWSE1Z18R6VHR"] == .partialOutage)
        #expect(status.componentStatuses["sora"] == nil)
    }

    /// And when *every* configured id has gone, the feed says it does not know rather
    /// than borrowing the page's overall indicator, which covers Sora, Images and 20-odd
    /// other products that say nothing about Codex.
    @Test func codexFilter_reportsUnknownWhenNoConfiguredComponentRemains() {
        let status = StatusChecker.parseStatus(
            summary(components: [sora]), config: StatusFeedConfig.codex
        )

        #expect(status.indicator == .unknown)
    }
}
