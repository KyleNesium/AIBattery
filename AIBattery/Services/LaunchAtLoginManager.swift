import ServiceManagement

/// Manages Launch at Login via SMAppService.
/// Requires an installed .app bundle — silently fails during development builds.
///
/// Ad-hoc signed apps lose their BTM (Background Task Management) registration
/// when the binary is re-signed (e.g. after a Sparkle update). `reregisterIfNeeded()`
/// detects this drift and re-registers on every launch.
public enum LaunchAtLoginManager {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                AppLogger.general.info("Launch at Login registered (status: \(SMAppService.mainApp.status.rawValue, privacy: .public))")
            } else {
                try SMAppService.mainApp.unregister()
                AppLogger.general.info("Launch at Login unregistered")
            }
        } catch {
            AppLogger.general.warning("Launch at Login toggle failed: \(error.localizedDescription, privacy: .public) (status: \(SMAppService.mainApp.status.rawValue, privacy: .public))")
        }
    }

    /// Re-register if the user preference is on but the system registration was lost
    /// (e.g. after ad-hoc re-signing from a Sparkle update).
    public static func reregisterIfNeeded() {
        let wantsLaunchAtLogin = UserDefaults.standard.bool(forKey: UserDefaultsKeys.launchAtLogin)
        guard wantsLaunchAtLogin else { return }

        let status = SMAppService.mainApp.status
        if status != .enabled {
            AppLogger.general.info("Launch at Login drift detected (status: \(status.rawValue, privacy: .public)), re-registering...")
            setEnabled(true)
        }
    }
}
