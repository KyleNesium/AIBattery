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
            statusBarManager.setup(viewModel: viewModel, oauthManager: oauthManager)
            LaunchAtLoginManager.reregisterIfNeeded()
            // One-shot launch maintenance: clear orphaned token-ledger entries
            // (resolved pending-* ids, removed accounts, stray test ids).
            oauthManager.pruneOrphanedLedgerAccounts()
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
