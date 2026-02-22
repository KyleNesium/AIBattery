import Foundation

/// Centralized UserDefaults keys — single source of truth to prevent typo bugs.
enum UserDefaultsKeys {
    static let metricMode = "aibattery_metricMode"
    static let refreshInterval = "aibattery_refreshInterval"
    static let tokenWindowDays = "aibattery_tokenWindowDays"
    static let alertClaudeAI = "aibattery_alertClaudeAI"
    static let alertClaudeCode = "aibattery_alertClaudeCode"
    static let chartMode = "aibattery_chartMode"
    static let plan = "aibattery_plan"
    static let accounts = "aibattery_accounts"
    static let activeAccountId = "aibattery_activeAccountId"
    static let launchAtLogin = "aibattery_launchAtLogin"
    static let alertRateLimit = "aibattery_alertRateLimit"
    static let rateLimitThreshold = "aibattery_rateLimitThreshold"
    static let showCostEstimate = "aibattery_showCostEstimate"
    static let showTokens = "aibattery_showTokens"
    static let showActivity = "aibattery_showActivity"
    static let lastUpdateCheck = "aibattery_lastUpdateCheck"
    static let colorblindMode = "aibattery_colorblindMode"
    static let hasSeenTutorial = "aibattery_hasSeenTutorial"
}
