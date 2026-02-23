import AIBatteryCore
import SwiftUI

@main
struct AIBatteryApp: App {
    @StateObject private var viewModel = UsageViewModel()
    @StateObject private var oauthManager = OAuthManager.shared

    init() {
        SingleInstanceGuard.ensureSingleInstance()
        SingleInstanceGuard.installSignalHandlers()
        SingleInstanceGuard.checkQuarantine()
        // Initialize early so status alert deduplication state is ready
        _ = NotificationManager.shared
    }

    var body: some Scene {
        MenuBarExtra {
            if oauthManager.isAuthenticated {
                UsagePopoverView(viewModel: viewModel)
            } else {
                AuthView(oauthManager: oauthManager)
            }
        } label: {
            MenuBarLabel(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
        .onChange(of: oauthManager.isAuthenticated) { authenticated in
            if authenticated {
                Task { await viewModel.refresh() }
            }
        }
    }
}
