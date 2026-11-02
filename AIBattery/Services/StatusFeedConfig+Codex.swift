import Foundation

extension StatusFeedConfig {
    /// status.openai.com — Statuspage-*shaped* but **not** Atlassian Statuspage, unlike
    /// status.claude.com, and its endpoints disagree about what they carry.
    ///
    /// **This reads `components.json`, not `summary.json`, deliberately.**
    /// `summary.json` is capped at the first **25** components by `position`, and all
    /// five Codex rows sit at positions 30–33 — so four of the five ids below were
    /// simply *absent from every response*, and the feed could never have seen them.
    /// `components.json` returns all 37 and every Codex id resolves in it (verified
    /// 2026-11-02). What that endpoint omits — a page-level `status` and `incidents` —
    /// is exactly what a filtered feed does not use: `parseStatus` reports `.unknown`
    /// rather than borrow a roll-up covering Sora, Ads and twenty others, and an
    /// OpenAI incident carries no `components` array, so it could never name a Codex
    /// component to escalate on. The component statuses are the whole signal here.
    ///
    /// Do not "fix" this back to `summary.json` because the Claude feed uses it, and do
    /// not re-tighten `StatusPageSummary`'s optionals by analogy with that feed.
    ///
    /// Component IDs read 2026-09-21, all five re-verified against `components.json` on
    /// 2026-11-02. Filtered to the Codex surfaces only: the page also lists Sora, Images,
    /// Realtime, Ads, … whose outages have nothing to do with Codex quota. The `name`s
    /// here are the ones the **settings alert list** shows, and stay qualified where the
    /// API's own are bare ("CLI", "VS Code extension") — those read as unrelated products
    /// in a list that also has Claude components.
    static let codex = StatusFeedConfig(
        summaryURL: URL(string: "https://status.openai.com/api/v2/components.json")!,
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
