import Foundation

/// Checks GitHub Releases for new versions. Fetches once per 24 hours.
public final class VersionChecker {
    public static let shared = VersionChecker()

    struct UpdateInfo {
        let version: String  // e.g. "1.2.0"
        let url: String      // release page URL
    }

    private let releaseURL = URL(string: "https://api.github.com/repos/KyleNesium/AIBattery/releases/latest")!
    private let checkInterval: TimeInterval = 86400 // 24 hours
    private var lastCheck: Date?
    private var cachedUpdate: UpdateInfo?

    private init() {}

    // MARK: - Public

    /// Check for updates if enough time has passed. Returns nil if up-to-date or check skipped.
    func checkForUpdate() async -> UpdateInfo? {
        if let lastCheck, Date().timeIntervalSince(lastCheck) < checkInterval {
            return cachedUpdate
        }

        let skipVersion = UserDefaults.standard.string(forKey: UserDefaultsKeys.skipVersion)
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
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: UserDefaultsKeys.lastUpdateCheck)

            if Self.isNewer(latestVersion, than: currentVersion) {
                if skipVersion == latestVersion {
                    cachedUpdate = nil
                    return nil
                }
                let update = UpdateInfo(version: latestVersion, url: htmlURL)
                cachedUpdate = update
                return update
            }

            cachedUpdate = nil
            return nil
        } catch {
            AppLogger.network.warning("Update check failed: \(error.localizedDescription, privacy: .public)")
            lastCheck = Date()
            return nil
        }
    }

    /// Dismiss the update for a specific version.
    func skipVersion(_ version: String) {
        UserDefaults.standard.set(version, forKey: UserDefaultsKeys.skipVersion)
        cachedUpdate = nil
    }

    // MARK: - Semver Comparison

    /// Strip leading "v" or "V" from a tag name.
    static func stripTag(_ tag: String) -> String {
        var t = tag
        if t.hasPrefix("v") || t.hasPrefix("V") {
            t = String(t.dropFirst())
        }
        return t
    }

    /// True if `latest` is a newer semver than `current`.
    static func isNewer(_ latest: String, than current: String) -> Bool {
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
    static var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
}
