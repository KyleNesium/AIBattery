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
            _ = NotificationManager.shared
            #if ENABLE_SPARKLE
            _ = SparkleUpdateService.shared
            #endif
            #if APP_SANDBOX
            _ = SandboxAccessManager.shared.startAccessing()
            #endif
            statusBarManager.setup(viewModel: viewModel, oauthManager: oauthManager)
        }
    }

    #if APP_SANDBOX
    nonisolated func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            SandboxAccessManager.shared.stopAccessing()
        }
    }
    #endif
}

@main
struct AIBatteryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
