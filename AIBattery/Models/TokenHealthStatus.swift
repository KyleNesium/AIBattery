import Foundation

/// Overall health band for token usage.
enum HealthBand: String {
    case green = "Optimal"
    case orange = "Warning"
    case red = "Critical"
    case unknown = "No Data"
}

/// A warning from cruft detection.
struct HealthWarning: Identifiable {
    let id = UUID()
    let severity: WarningSeverity
    let message: String
    let suggestion: String?

    enum WarningSeverity {
        case mild, strong
    }
}

/// Complete health assessment for a session.
struct TokenHealthStatus: Identifiable {
    let id: String  // sessionId
    let band: HealthBand
    let usagePercentage: Double
    let totalUsed: Int
    let contextWindow: Int
    let usableWindow: Int       // contextWindow × 0.8 (auto-compact threshold)
    let remainingTokens: Int    // usableWindow - totalUsed
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int
    let model: String
    let turnCount: Int
    let warnings: [HealthWarning]
    let tokensPerMinute: Double?
    let projectName: String?
    let gitBranch: String?
    let sessionStart: Date?
    let sessionDuration: TimeInterval?
    let lastActivity: Date?           // timestamp of most recent entry in this session

    var suggestedAction: String? {
        switch band {
        case .orange:
            return "Consider trimming context or starting a fresh conversation soon."
        case .red:
            return "Start a new conversation for best results. Context degradation is likely."
        case .green, .unknown:
            return nil
        }
    }
}
