import Foundation

/// Centralized UserDefaults keys — single source of truth to prevent typo bugs.
enum UserDefaultsKeys {
    static let metricMode = "aibattery_metricMode"
    static let refreshInterval = "aibattery_refreshInterval"
    static let chartMode = "aibattery_chartMode"
    static let plan = "aibattery_plan"
    static let accounts = "aibattery_accounts"
    static let activeAccountId = "aibattery_activeAccountId"
    static let launchAtLogin = "aibattery_launchAtLogin"
    static let alertStatus = "aibattery_alertStatus"
    static let alertRateLimit = "aibattery_alertRateLimit"
    static let rateLimitThreshold = "aibattery_rateLimitThreshold"
    // showCostEstimate removed — cost always visible since v1.9.0
    static let lastUpdateCheck = "aibattery_lastUpdateCheck"
    static let lastUpdateVersion = "aibattery_lastUpdateVersion"
    static let lastUpdateURL = "aibattery_lastUpdateURL"
    static let autoMetricMode = "aibattery_autoMetricMode"
    static let colorblindMode = "aibattery_colorblindMode"
    static let hasSeenTutorial = "aibattery_hasSeenTutorial"
    static let idleSessionMinutes = "aibattery_idleSessionMinutes"
    static let throttleTimestamps = "aibattery_throttleTimestamps"
    static let planTier = "aibattery_planTier"
    static let contextCollapsed = "aibattery_contextCollapsed"
    // tokensCollapsed removed — Tokens section merged into Insights since v1.9.0
    static let projectsCollapsed = "aibattery_projectsCollapsed"
    static let activityCollapsed = "aibattery_activityCollapsed"
    /// Prefix for per-account token expiry timestamps (append account ID).
    static let tokenExpiresAtPrefix = "aibattery_expiresAt_"
}
