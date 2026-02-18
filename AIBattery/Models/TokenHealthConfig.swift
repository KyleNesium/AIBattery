import Foundation

/// Configurable thresholds for token health monitoring.
struct TokenHealthConfig {
    /// Context window limits per model (in tokens).
    static let contextWindows: [String: Int] = [
        "claude-opus-4-6": 200_000,
        "claude-sonnet-4-5-20250929": 200_000,
        "claude-haiku-4-5-20251001": 200_000,
        // Older models
        "claude-3-5-sonnet-20241022": 200_000,
        "claude-3-5-haiku-20241022": 200_000,
        "claude-3-opus-20240229": 200_000,
        "claude-3-sonnet-20240229": 200_000,
        "claude-3-haiku-20240307": 200_000,
    ]

    /// Pre-computed 3-part prefix lookup for fuzzy model matching.
    /// Built once at load time — avoids repeated string splitting in the hot path.
    private static let prefixLookup: [String: Int] = {
        var lookup: [String: Int] = [:]
        for (key, value) in contextWindows {
            let prefix = key.split(separator: "-").prefix(3).joined(separator: "-")
            lookup[prefix] = value
        }
        return lookup
    }()

    /// Default context window if model not found.
    static let defaultContextWindow = 200_000

    // MARK: - Usable context

    /// Claude Code auto-compacts at 80% of context window.
    /// Percentages are calculated against this usable portion, not the raw window.
    static let usableContextRatio: Double = 0.80

    // MARK: - Primary band thresholds (percentage of usable window)

    /// Below this: green (optimal)
    var greenThreshold: Double = 60.0
    /// Below this: orange (warning); above: red (critical)
    var redThreshold: Double = 80.0

    // MARK: - Turn count thresholds

    /// Below this: no flag
    var turnCountMild: Int = 15
    /// Below this: mild warning; above: strong warning
    var turnCountStrong: Int = 25

    // MARK: - Input/output ratio threshold

    /// Flag when input:output ratio exceeds this
    var inputOutputRatioThreshold: Double = 20.0

    static let `default` = TokenHealthConfig()

    static func contextWindow(for model: String) -> Int {
        // Try exact match first (O(1) dictionary lookup)
        if let window = contextWindows[model] { return window }
        // Try prefix match via pre-computed lookup (no string allocations per key)
        let modelPrefix = model.split(separator: "-").prefix(3).joined(separator: "-")
        if let window = prefixLookup[modelPrefix] { return window }
        return defaultContextWindow
    }
}
