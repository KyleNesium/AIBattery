import Foundation

extension StatusFeedConfig {
    /// status.openai.com — Statuspage-*shaped* but **not** Atlassian Statuspage, unlike
    /// status.claude.com. Its `page` object carries a ULID rather than a Statuspage hex
    /// id, and it omits `incidents` and `scheduled_maintenances` entirely, which is why
    /// `StatusPageSummary.incidents` decodes as optional — requiring it threw on every
    /// single poll. Do not re-tighten it by analogy with the Claude feed.
    ///
    /// Component IDs read from the live summary on 2026-09-21. Filtered to the Codex
    /// surfaces only: the page also lists Sora, Images, Realtime, Ads, … whose outages
    /// have nothing to do with Codex quota. **Four of these five ids no longer exist**
    /// (checked 2026-11-02 — the page reorganised and now carries one Codex row, "Codex
    /// in ChatGPT Desktop"). A missing id is handled, not fatal: `parseStatus` filters
    /// it out, and a filtered feed whose components have all vanished reports `.unknown`
    /// rather than the page's unrelated overall indicator. Which surfaces should stand
    /// for "Codex is degraded" now is a product call, so the list is left as recorded.
    static let codex = StatusFeedConfig(
        summaryURL: URL(string: "https://status.openai.com/api/v2/summary.json")!,
        statusPageBaseURL: "https://status.openai.com",
        knownComponents: codexComponents,
        componentFilter: Set(codexComponents.map(\.id))
    )

    private static let codexComponents: [StatusComponent] = [
        StatusComponent(id: "01KMP3KP5MGE23B80K1EK4S8PV", name: "Codex API", alertKey: "codexAPI"),
        StatusComponent(id: "01KMKFAMWKNQ84Z1766MV08ZDE", name: "Codex CLI", alertKey: "codexCLI"),
        StatusComponent(id: "01KMKFAMWKQ81YWSE1Z18R6VHR", name: "Codex in ChatGPT Desktop", alertKey: "codexDesktop"),
        StatusComponent(id: "01JVCV8YSWZFRSM1G5CVP253SK", name: "Codex Web", alertKey: "codexWeb"),
        StatusComponent(id: "01KMP3KP5M8X0EBTVW6KN327EE", name: "Codex VS Code extension", alertKey: "codexVSCode"),
    ]
}
