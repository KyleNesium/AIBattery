import Foundation

/// Centralized UserDefaults keys — single source of truth to prevent typo bugs.
enum UserDefaultsKeys {
    static let metricMode = "aibattery_metricMode"
    static let orgName = "aibattery_orgName"
    static let displayName = "aibattery_displayName"
    static let refreshInterval = "aibattery_refreshInterval"
    static let tokenWindowDays = "aibattery_tokenWindowDays"
    static let alertClaudeAI = "aibattery_alertClaudeAI"
    static let alertClaudeCode = "aibattery_alertClaudeCode"
    static let chartMode = "aibattery_chartMode"
    static let plan = "aibattery_plan"
    static let accounts = "aibattery_accounts"
    static let activeAccountId = "aibattery_activeAccountId"
}
