import Foundation

/// Checks GitHub Releases for new versions. Fetches once per 24 hours.
@MainActor
public final class VersionChecker {
    public static let shared = VersionChecker()

    struct UpdateInfo {
        let version: String  // e.g. "1.2.0"
        let url: String      // release page URL
    }

    private let releaseURL: URL
    let checkInterval: TimeInterval
    /// Visible to tests via @testable import.
    var lastCheck: Date?
    /// Visible to tests via @testable import.
    var cachedUpdate: UpdateInfo?

    /// Singleton init — uses real GitHub API and 24h cache.
    /// Restores last check time and cached update from UserDefaults.
    private convenience init() {
        self.init(
            releaseURL: URL(string: "https://api.github.com/repos/KyleNesium/AIBattery/releases/latest")!,
            checkInterval: 86400
        )
        restoreFromDefaults()
    }

    /// Testable init — accepts a custom URL and cache interval.
    /// Does NOT restore from UserDefaults to keep tests isolated.
    init(releaseURL: URL, checkInterval: TimeInterval = 86400) {
        self.releaseURL = releaseURL
        self.checkInterval = checkInterval
    }

    // MARK: - Public

    /// Check for updates if enough time has passed. Returns nil if up-to-date or check skipped.
    func checkForUpdate() async -> UpdateInfo? {
        if let lastCheck, Date().timeIntervalSince(lastCheck) < checkInterval {
            return cachedUpdate
        }

        let currentVersion = Self.currentAppVersion

        do {
            var request = URLRequest(url: releaseURL)
            request.timeoutInterval = 10
            request.setValue("AIBattery", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                lastCheck = Date()
                return nil
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let htmlURL = json["html_url"] as? String else {
                lastCheck = Date()
                return nil
            }

            let latestVersion = Self.stripTag(tagName)
            lastCheck = Date()

            if Self.isNewer(latestVersion, than: currentVersion) {
                let update = UpdateInfo(version: latestVersion, url: htmlURL)
                cachedUpdate = update
            } else {
                cachedUpdate = nil
            }

            persistToDefaults()
            return cachedUpdate
        } catch {
            AppLogger.network.warning("Update check failed: \(error.localizedDescription, privacy: .public)")
            lastCheck = Date()
            persistToDefaults()
            return nil
        }
    }

    /// Force-check for updates, ignoring the 24-hour cache.
    func forceCheckForUpdate() async -> UpdateInfo? {
        lastCheck = nil
        cachedUpdate = nil
        return await checkForUpdate()
    }

    // MARK: - Semver Comparison

    /// Strip leading "v" or "V" from a tag name.
    nonisolated static func stripTag(_ tag: String) -> String {
        var t = tag
        if t.hasPrefix("v") || t.hasPrefix("V") {
            t = String(t.dropFirst())
        }
        return t
    }

    /// True if `latest` is a newer semver than `current`.
    nonisolated static func isNewer(_ latest: String, than current: String) -> Bool {
        let latestParts = latest.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }

        let maxLen = max(latestParts.count, currentParts.count)
        for i in 0..<maxLen {
            let l = i < latestParts.count ? latestParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            if l > c { return true }
            if l < c { return false }
        }
        return false
    }

    /// Current app version from the bundle, falling back to "0.0.0".
    nonisolated static var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    // MARK: - UserDefaults Persistence

    /// Restore last check time and cached update from UserDefaults.
    private func restoreFromDefaults() {
        let ts = UserDefaults.standard.double(forKey: UserDefaultsKeys.lastUpdateCheck)
        if ts > 0 {
            lastCheck = Date(timeIntervalSince1970: ts)
        }
        if let version = UserDefaults.standard.string(forKey: UserDefaultsKeys.lastUpdateVersion),
           let url = UserDefaults.standard.string(forKey: UserDefaultsKeys.lastUpdateURL) {
            // Only restore if cached version is still newer than current (avoids stale banner after upgrade)
            if Self.isNewer(version, than: Self.currentAppVersion) {
                cachedUpdate = UpdateInfo(version: version, url: url)
            } else {
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.lastUpdateVersion)
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.lastUpdateURL)
            }
        }
    }

    /// Persist last check time and cached update to UserDefaults.
    private func persistToDefaults() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: UserDefaultsKeys.lastUpdateCheck)
        if let update = cachedUpdate {
            UserDefaults.standard.set(update.version, forKey: UserDefaultsKeys.lastUpdateVersion)
            UserDefaults.standard.set(update.url, forKey: UserDefaultsKeys.lastUpdateURL)
        } else {
            UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.lastUpdateVersion)
            UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.lastUpdateURL)
        }
    }
}
