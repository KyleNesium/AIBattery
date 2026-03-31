import SwiftUI

/// Launch at Login toggle.
struct LaunchAtLoginSection: View {
    @AppStorage(UserDefaultsKeys.launchAtLogin) private var launchAtLogin: Bool = false

    var body: some View {
        HStack(spacing: Spacing.section) {
            Text("Startup")
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .frame(width: Layout.settingsLabel, alignment: .trailing)
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .font(Typography.caption)
                .help("Start AI Battery when you log in to macOS")
                .onAppear {
                    launchAtLogin = LaunchAtLoginManager.isEnabled
                }
                .onChange(of: launchAtLogin) { newValue in
                    LaunchAtLoginManager.setEnabled(newValue)
                }
        }
    }
}
