import AIBatteryCore
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = UsageViewModel()
    let oauthManager = OAuthManager.shared
    let statusBarManager = StatusBarManager()

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            SingleInstanceGuard.ensureSingleInstance()
            SingleInstanceGuard.installSignalHandlers()
            SingleInstanceGuard.checkQuarantine()
            _ = NotificationManager.shared
            _ = SparkleUpdateService.shared
            statusBarManager.setup(viewModel: viewModel, oauthManager: oauthManager)
        }
    }
}

@main
struct AIBatteryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
