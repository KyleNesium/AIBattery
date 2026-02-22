import ServiceManagement

/// Manages Launch at Login via SMAppService.
/// Requires an installed .app bundle — silently fails during development builds.
enum LaunchAtLoginManager {
    @available(macOS 13.0, *)
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @available(macOS 13.0, *)
    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            AppLogger.general.warning("Launch at Login toggle failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
