import Foundation

extension StatusFeedConfig {
    /// status.openai.com — same Atlassian Statuspage schema as status.claude.com.
    /// Component IDs read from the live summary on 2026-09-21. Filtered to the Codex
    /// surfaces only: the page also lists Sora, Images, Realtime, Ads, … whose outages
    /// have nothing to do with Codex quota.
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
