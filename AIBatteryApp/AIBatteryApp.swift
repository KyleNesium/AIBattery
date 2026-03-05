import AIBatteryCore
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = UsageViewModel()
    let oauthManager = OAuthManager.shared
    let statusBarManager = StatusBarManager()
    #if APP_SANDBOX
    var needsSandboxOnboarding = false
    #endif

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            SingleInstanceGuard.ensureSingleInstance()
            SingleInstanceGuard.installSignalHandlers()
            _ = NotificationManager.shared
            #if ENABLE_SPARKLE
            _ = SparkleUpdateService.shared
            #endif
            #if APP_SANDBOX
            if !SandboxAccessManager.shared.startAccessing() {
                needsSandboxOnboarding = true
            }
            #endif
            statusBarManager.setup(viewModel: viewModel, oauthManager: oauthManager)
        }
    }

    #if APP_SANDBOX
    nonisolated func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
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
