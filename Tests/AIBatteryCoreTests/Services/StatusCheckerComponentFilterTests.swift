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

    /// Page-level status is deliberately set to something alarming the filtered feed must
    /// never surface: every Codex assertion below would pass for the wrong reason if the
    /// parser ever fell back to the roll-up instead of the filtered components.
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

    /// The Codex dot stays green during an OpenAI incident that does not touch Codex, so the
    /// status carries what else is degraded or down for the tooltip to name.
    @Test func filter_listsOtherAffectedServices_withoutColouringTheIndicator() {
        let images = StatusPageComponent(id: "images", name: "Images", status: "degraded_performance")
        let realtime = StatusPageComponent(id: "realtime", name: "Realtime", status: "under_maintenance")
        let ads = StatusPageComponent(id: "ads", name: "Ads", status: "operational")
        let page = summary(components: [codexAPI, sora, images, realtime, ads])

        let filtered = StatusChecker.parseStatus(page, config: config(filter: ["codex-api"]))
        #expect(filtered.indicator == .operational)
        #expect(filtered.otherAffectedServices == ["Sora", "Images"], "maintenance and operational are not faults")

        // An unfiltered feed watches everything, so nothing is "other".
        #expect(StatusChecker.parseStatus(page, config: config(filter: nil)).otherAffectedServices.isEmpty)
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
        #expect(summary.status?.indicator == "none")
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

    /// The Codex feed must read `components.json`, **not** `summary.json`.
    ///
    /// `summary.json` is capped at the first 25 components by position and every Codex
    /// row sits at 30–33, so four of the five configured ids are absent from every
    /// response it can ever return — the feed could not have seen them even once the
    /// decode was fixed. This is the regression guard: pointing it back at `summary.json`
    /// to match the Claude feed silently re-breaks four fifths of the signal.
    @Test func codexFeed_readsTheEndpointThatListsEveryComponent() {
        #expect(StatusFeedConfig.codex.summaryURL.absoluteString
            == "https://status.openai.com/api/v2/components.json")
        #expect(StatusFeedConfig.claude.summaryURL.absoluteString
            == "https://status.claude.com/api/v2/summary.json")
    }

    /// `components.json` carries neither a page-level `status` nor `incidents`, so both
    /// decode as optional. Payload trimmed from the live response (2026-11-02), keys and
    /// nesting intact.
    @Test func decode_componentsOnlyPayloadWithNoStatusOrIncidents() throws {
        let json = Data("""
        {
          "page": { "id": "01JMDK9XYNY6RXSED6SDWW50WY", "name": "OpenAI" },
          "components": [
            { "id": "01KMP3KP5MGE23B80K1EK4S8PV", "name": "Codex API", "status": "operational" },
            { "id": "01KMKFAMWKNQ84Z1766MV08ZDE", "name": "CLI", "status": "degraded_performance" }
          ]
        }
        """.utf8)

        let summary = try JSONDecoder().decode(StatusPageSummary.self, from: json)

        #expect(summary.status == nil)
        #expect(summary.incidents.isEmpty)
        #expect(summary.components.count == 2)
    }

    /// Every configured Codex id drives the indicator, and the bare API names the Codex
    /// rows actually carry ("CLI", not "Codex CLI") still resolve — the filter matches on
    /// id, and the qualified names in the config are only for the settings alert list.
    @Test func codexFilter_matchesEveryConfiguredCodexComponent() {
        let codexIds = [
            "01KMP3KP5MGE23B80K1EK4S8PV", // Codex API
            "01KMKFAMWKNQ84Z1766MV08ZDE", // CLI
            "01KMKFAMWKQ81YWSE1Z18R6VHR", // Codex in ChatGPT Desktop
            "01JVCV8YSWZFRSM1G5CVP253SK", // Codex Web
            "01KMP3KP5M8X0EBTVW6KN327EE", // VS Code extension
        ]
        #expect(Set(codexIds) == StatusFeedConfig.codex.componentFilter)

        let components = codexIds.map {
            StatusPageComponent(id: $0, name: "CLI", status: "operational")
        } + [sora]
        let healthy = StatusChecker.parseStatus(
            summary(components: components), config: StatusFeedConfig.codex
        )
        #expect(healthy.indicator == .operational)
        #expect(healthy.componentStatuses.count == codexIds.count)
        #expect(healthy.componentStatuses["sora"] == nil)

        // Any one of them going down must surface, not just the ChatGPT Desktop row.
        for id in codexIds {
            let degraded = components.map {
                $0.id == id
                    ? StatusPageComponent(id: $0.id, name: $0.name, status: "major_outage")
                    : $0
            }
            let status = StatusChecker.parseStatus(
                summary(components: degraded), config: StatusFeedConfig.codex
            )
            #expect(status.indicator == .majorOutage, "\(id) did not drive the indicator")
        }
    }

    /// When no configured id is present the feed says it does not know, rather than
    /// borrowing a page roll-up that covers Sora, Ads and twenty other products.
    @Test func codexFilter_reportsUnknownWhenNoConfiguredComponentIsPresent() {
        let status = StatusChecker.parseStatus(
            summary(components: [sora]), config: StatusFeedConfig.codex
        )

        #expect(status.indicator == .unknown)
    }

    /// An unfiltered feed falls back to the page roll-up — but only when the payload has
    /// one. No page-level status means unknown, never "operational".
    @Test func noFilter_withoutPageStatus_reportsUnknown() {
        let noStatus = StatusPageSummary(status: nil, components: [], incidents: [])
        let status = StatusChecker.parseStatus(noStatus, config: config(filter: nil))

        #expect(status.indicator == .unknown)
    }
}
