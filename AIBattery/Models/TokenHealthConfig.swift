import Foundation

/// Configurable thresholds for token health monitoring.
struct TokenHealthConfig {
    /// Claude context windows, from Anthropic's models overview (checked 2026-11-14): every
    /// model from the 4.6 generation on has 1M tokens, and everything before it — Opus 4.5,
    /// Sonnet 4.5, Haiku 4.5 and all earlier models — has 200K.
    ///
    /// A version rule rather than a table of ids, so a new model needs no entry. Until 3.5.0
    /// a table gave every 4.x model 1M, which made a Haiku 4.5 or Sonnet 4.5 session read as
    /// a fifth as full as it was.
    static let longContextFromVersion = [4, 6]
    static let legacyContextWindow = 200_000

    /// Window for a model newer than 4.6, and for an id with no recognisable version.
    static let defaultContextWindow = 1_000_000

    /// Codex (`gpt-*`) models: `model_context_window` as reported in Codex CLI
    /// `token_count` events (258 400 for the gpt-5.x family on Codex CLI 0.152).
    static let openAIDefaultContextWindow = 258_400

    // MARK: - Usable context

    /// Percentages are calculated against the full context window.
    /// With 1M context windows, the full window is usable.
    static let usableContextRatio: Double = 1.0

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

    // MARK: - Anomaly detection thresholds

    /// Session idle for this many minutes triggers a stale warning.
    var staleSessionMinutes: Int = 30
    /// Zero output after this many turns triggers a warning.
    var zeroOutputTurnThreshold: Int = 3

    // MARK: - Rapid consumption / velocity thresholds

    /// Session shorter than this (seconds) with high token usage triggers a warning.
    var rapidConsumptionSeconds: Int = 60
    /// Token threshold for rapid consumption detection.
    var rapidConsumptionTokens: Int = 50_000
    /// Minimum session duration (seconds) before velocity is calculated.
    var velocityMinDuration: TimeInterval = 60

    static let `default` = TokenHealthConfig()

    static func contextWindow(for model: String) -> Int {
        if model.hasPrefix("gpt-") {
            return openAIDefaultContextWindow
        }
        if let version = ModelNameMapper.claudeFamilyAndVersion(of: model)?.version, !version.isEmpty,
           version.lexicographicallyPrecedes(longContextFromVersion) {
            return legacyContextWindow
        }
        return defaultContextWindow
    }
}
