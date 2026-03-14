import Foundation

struct ProjectTokenSummary: Identifiable {
    let id: String              // project name (cwd lastPathComponent)
    let projectName: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int
    let estimatedCost: Double   // pre-computed from per-entry model pricing

    var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens
    }
}
