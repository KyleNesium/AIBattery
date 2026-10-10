import SwiftUI

/// Settings → About: app name + version, manual "Check for Updates", release notes,
/// and the Sparkle update-failed strip. The header keeps only the automatic
/// update-available banner; everything a user *does* about updates lives here.
struct AboutSection: View {
    @ObservedObject var viewModel: UsageViewModel

    #if ENABLE_VERSION_CHECKER
    @State private var checking = false
    @State private var checkMessage: String?
    @State private var checkDismissTask: Task<Void, Never>?
    #endif

    private static var version: String {
        #if ENABLE_VERSION_CHECKER
        VersionChecker.currentAppVersion
        #else
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            HStack(spacing: Spacing.section) {
                Text("About")
                    .font(Typography.caption)
                    .foregroundStyle(ThemeColors.secondaryLabel)
                    .frame(width: Layout.settingsLabel, alignment: .trailing)
                Image(systemName: "sparkle")
                    .font(Typography.caption)
                    .foregroundStyle(ThemeColors.secondaryLabel)
                    .accessibilityHidden(true)
                Text("AI Battery")
                    .font(Typography.caption)
                    .fontWeight(.semibold)
                Text("v\(Self.version)")
                    .font(Typography.monoCaption)
                    .foregroundStyle(ThemeColors.secondaryLabel)
                    .textSelection(.enabled)
                Spacer()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("AI Battery version \(Self.version)")

            HStack(spacing: Spacing.section) {
                Spacer().frame(width: Layout.settingsLabel)
                #if ENABLE_VERSION_CHECKER
                if let update = viewModel.availableUpdate {
                    LinkActionButton(
                        label: "Install v\(update.version)",
                        icon: "arrow.down.circle",
                        help: "Downloads and installs the update",
                        accessibilityLabel: "Install update version \(update.version)"
                    ) {
                        Self.installUpdate(update)
                    }
                } else {
                    LinkActionButton(
                        label: checking ? "Checking…" : "Check for Updates",
                        icon: "arrow.triangle.2.circlepath",
                        help: "Check GitHub for a newer release",
                        accessibilityLabel: "Check for updates"
                    ) {
                        checkForUpdates()
                    }
                    .disabled(checking)
                }
                #endif
                LinkActionButton(
                    label: "Release notes",
                    icon: "arrow.up.right",
                    help: "Open the release notes on GitHub",
                    accessibilityLabel: "Open release notes in your browser"
                ) {
                    if let url = URL(string: Self.releasesURL) {
                        NSWorkspace.shared.open(url)
                    }
                }
                Spacer()
            }

            #if ENABLE_VERSION_CHECKER
            if let message = checkMessage {
                HStack(spacing: Spacing.section) {
                    Spacer().frame(width: Layout.settingsLabel)
                    Image(systemName: "checkmark.circle.fill")
                        .font(Typography.tinyLabel)
                        .foregroundStyle(ThemeColors.success)
                    Text(message)
                        .font(Typography.tinyLabel)
                        .foregroundStyle(ThemeColors.secondaryLabel)
                }
                .transition(.opacity)
            }
            #if ENABLE_SPARKLE
            if let sparkleError = SparkleUpdateService.shared.lastError {
                HStack(spacing: Spacing.section) {
                    Spacer().frame(width: Layout.settingsLabel)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(Typography.tinyLabel)
                        .foregroundStyle(ThemeColors.danger)
                    Text("Update failed")
                        .font(Typography.tinyLabel)
                        .foregroundStyle(ThemeColors.secondaryLabel)
                    LinkActionButton(
                        label: "Download",
                        size: .compact,
                        accessibilityLabel: "Download the latest release",
                        accessibilityHint: "Opens the GitHub release page in your browser"
                    ) {
                        if let url = URL(string: Self.latestReleaseURL) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Button(action: { SparkleUpdateService.shared.clearError() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(Typography.monoTiny)
                            .foregroundStyle(ThemeColors.secondaryLabel)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss update error")
                    .accessibilityHint("Hides the update-failed message")
                }
                .help(sparkleError)
                .transition(.opacity)
            }
            #endif
            #endif
        }
        .onDisappear {
            #if ENABLE_VERSION_CHECKER
            checkDismissTask?.cancel()
            #endif
        }
    }

    static let releasesURL = "https://github.com/KyleNesium/AIBattery/releases"
    static let latestReleaseURL = "https://github.com/KyleNesium/AIBattery/releases/latest"

    #if ENABLE_VERSION_CHECKER
    /// Sparkle in-app update when it is ready, else the GitHub release page.
    /// Shared with the header's update banner so both paths behave identically.
    static func installUpdate(_ update: VersionChecker.UpdateInfo) {
        #if ENABLE_SPARKLE
        if SparkleUpdateService.shared.canCheckForUpdates {
            SparkleUpdateService.shared.checkForUpdates()
            return
        }
        #endif
        if let url = URL(string: update.url) {
            NSWorkspace.shared.open(url)
        }
    }

    private func checkForUpdates() {
        checking = true
        Task {
            let result = await VersionChecker.shared.forceCheckForUpdate()
            viewModel.availableUpdate = result
            checking = false
            guard result == nil else {
                checkMessage = nil
                return
            }
            checkMessage = "Up to date"
            checkDismissTask?.cancel()
            checkDismissTask = Task {
                try? await Task.sleep(nanoseconds: MotionConstants.updateCheckMessageNs)
                guard !Task.isCancelled else { return }
                checkMessage = nil
            }
        }
    }
    #endif
}
