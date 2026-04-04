import Foundation

struct ProjectTokenSummary: Identifiable, Equatable {
    let id: String              // full cwd path (unique key; "Other" for nil cwd)
    let projectName: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int
    let estimatedCost: Double   // pre-computed from per-entry model pricing

    var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens
    }

    /// Input + output only — actual consumption excluding cache.
    var usageTokens: Int {
        inputTokens + outputTokens
    }
}
