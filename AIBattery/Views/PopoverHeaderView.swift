import SwiftUI

struct PopoverHeaderView: View {
    let snapshot: UsageSnapshot?
    @ObservedObject var accountStore: AccountStore
    @Binding var showSettings: Bool
    @Binding var isAddingAccount: Bool
    let onSwitchAccount: (String) -> Void
    let onUpdateFound: (VersionChecker.UpdateInfo?) -> Void
    let availableUpdate: VersionChecker.UpdateInfo?

    @State private var gearHovered = false
    #if ENABLE_VERSION_CHECKER
    @State private var updateCheckMessage: String?
    @State private var updateCheckDismissTask: Task<Void, Never>?
    @State private var updateBannerDismissed = false
    @State private var updateHovered = false
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.inner) {
            HStack(alignment: .center, spacing: Spacing.inner) {
                Image(systemName: "sparkle")
                    .font(Typography.heroValue)
                    .foregroundStyle(.primary)
                Text("AI Battery")
                    .font(Typography.sectionHeader)
                    .fixedSize()
                accountPicker
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                #if ENABLE_VERSION_CHECKER
                Text("v\(VersionChecker.currentAppVersion)")
                    .font(Typography.monoTiny)
                    .foregroundStyle(ThemeColors.tertiaryLabel)
                Button(action: {
                    if availableUpdate != nil {
                        updateBannerDismissed = false
                    } else {
                        Task {
                            let result = await VersionChecker.shared.forceCheckForUpdate()
                            onUpdateFound(result)
                            if result == nil {
                                updateCheckMessage = "Up to date"
                                updateCheckDismissTask?.cancel()
                                updateCheckDismissTask = Task {
                                    try? await Task.sleep(nanoseconds: MotionConstants.updateCheckMessageNs)
                                    guard !Task.isCancelled else { return }
                                    updateCheckMessage = nil
                                }
                            } else {
                                updateCheckMessage = nil
                            }
                        }
                    }
                }) {
                    Image(systemName: "arrow.up.circle")
                        .font(Typography.bodyLabel)
                }
                .buttonStyle(.plain)
                .foregroundStyle(
                    availableUpdate != nil ? ThemeColors.updateAvailable
                        : updateCheckMessage != nil ? ThemeColors.success
                        : updateHovered ? .primary : .secondary
                )
                .onHover { updateHovered = $0 }
                .help(availableUpdate.map { "v\($0.version) available" } ?? "Check for updates")
                .accessibilityLabel(availableUpdate.map { "Version \($0.version) available" } ?? "Check for updates")
                #else
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0")")
                    .font(Typography.monoTiny)
                    .foregroundStyle(ThemeColors.tertiaryLabel)
                #endif
                Button(action: { withAnimation(MotionConstants.standard) { showSettings.toggle() } }) {
                    Image(systemName: "gearshape")
                        .font(Typography.bodyLabel)
                }
                .buttonStyle(.plain)
                .foregroundStyle(showSettings || gearHovered ? .primary : .secondary)
                .onHover { gearHovered = $0 }
                .help("Settings")
                .accessibilityLabel("Settings")
                .accessibilityHint(showSettings ? "Close settings" : "Open settings")
            }

            #if ENABLE_VERSION_CHECKER
            // Update status message (appears/disappears below header row)
            if let update = availableUpdate, !updateBannerDismissed {
                HStack(spacing: Spacing.gap) {
                    Button(action: {
                        if let url = URL(string: update.url) {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: Spacing.xsmall) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(Typography.tinyLabel)
                                .foregroundStyle(ThemeColors.updateAvailable)
                            Text("v\(update.version)")
                                .font(Typography.tinyLabel)
                                .foregroundStyle(ThemeColors.secondaryLabel)
                            Image(systemName: "arrow.up.right")
                                .font(Typography.decorativeIcon)
                                .foregroundStyle(ThemeColors.tertiaryLabel)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Version \(update.version) release notes")
                    Button(action: {
                        #if ENABLE_SPARKLE
                        if SparkleUpdateService.shared.canCheckForUpdates {
                            SparkleUpdateService.shared.checkForUpdates()
                        } else if let url = URL(string: update.url) {
                            NSWorkspace.shared.open(url)
                        }
                        #else
                        if let url = URL(string: update.url) {
                            NSWorkspace.shared.open(url)
                        }
                        #endif
                    }) {
                        HStack(spacing: Spacing.xsmall) {
                            Image(systemName: "arrow.down.circle")
                                .font(Typography.monoTiny)
                            Text("Install Update")
                                .font(Typography.tinyLabel)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ThemeColors.action)
                    .accessibilityLabel("Install update version \(update.version)")
                    Spacer()
                    Button(action: { updateBannerDismissed = true }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(Typography.heroTitle)
                            .foregroundStyle(ThemeColors.secondaryLabel)
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss")
                    .accessibilityLabel("Dismiss update banner")
                }
                .padding(Spacing.section)
                .background(
                    RoundedRectangle(cornerRadius: Layout.bannerCornerRadius)
                        .fill(ThemeColors.updateAvailable.opacity(ThemeColors.subtleElementOpacity))
                        .overlay(
                            RoundedRectangle(cornerRadius: Layout.bannerCornerRadius)
                                .stroke(ThemeColors.updateAvailable.opacity(ThemeColors.subtleStrokeOpacity), lineWidth: Layout.subtleBorderWidth)
                        )
                )
                .padding(.horizontal, -Spacing.tight)
                .transition(MotionConstants.expandTransition)
            } else if let msg = updateCheckMessage {
                HStack(spacing: Spacing.inner) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(Typography.tinyLabel)
                        .foregroundStyle(ThemeColors.success)
                    Text(msg)
                        .font(Typography.tinyLabel)
                        .foregroundStyle(ThemeColors.secondaryLabel)
                }
                .transition(.opacity)
            }
            #if ENABLE_SPARKLE
            if let sparkleError = SparkleUpdateService.shared.lastError {
                HStack(spacing: Spacing.gap) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(Typography.tinyLabel)
                        .foregroundStyle(ThemeColors.danger)
                    Text("Update failed")
                        .font(Typography.tinyLabel)
                        .foregroundStyle(ThemeColors.secondaryLabel)
                    Spacer()
                    Button(action: {
                        if let url = URL(string: "https://github.com/KyleNesium/AIBattery/releases/latest") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        Text("Download")
                            .font(Typography.tinyLabel)
                            .foregroundStyle(ThemeColors.action)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Download the latest release")
                    .accessibilityHint("Opens the GitHub release page in your browser")
                    Button(action: { SparkleUpdateService.shared.clearError() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(Typography.monoTiny)
                            .foregroundStyle(ThemeColors.secondaryLabel)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss update error")
                    .accessibilityHint("Hides the update-failed banner")
                }
                .help(sparkleError)
                .transition(.opacity)
            }
            #endif
            #endif
        }
        .padding(.horizontal, Spacing.sectionHorizontal)
        .padding(.vertical, Spacing.section)
        .onDisappear {
            #if ENABLE_VERSION_CHECKER
            updateCheckDismissTask?.cancel()
            #endif
        }
    }

    /// Account picker — shows display name if set, otherwise "User N".
    private var accountPicker: some View {
        Menu {
            let activeId = accountStore.activeAccountId
            ForEach(Array(accountStore.accounts.enumerated()), id: \.element.id) { index, account in
                Button(action: {
                    withAnimation(MotionConstants.standard) {
                        onSwitchAccount(account.id)
                    }
                }) {
                    HStack {
                        Text(accountLabel(account, index: index))
                        if account.id == activeId {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            if accountStore.canAddAccount {
                Divider()
                Button(action: { isAddingAccount = true }) {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("Add Account")
                    }
                }
            }
        } label: {
            if let activeIndex = accountStore.accounts.firstIndex(where: { $0.id == accountStore.activeAccountId }) {
                Text(accountLabel(accountStore.accounts[activeIndex], index: activeIndex))
                    .font(Typography.caption)
                    .foregroundStyle(ThemeColors.secondaryLabel)
                    .lineLimit(1)
            } else {
                Text("Account")
                    .font(Typography.caption)
                    .foregroundStyle(ThemeColors.secondaryLabel)
                    .lineLimit(1)
            }
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: Layout.accountPickerMaxWidth)
        .accessibilityLabel("Switch account")
        .accessibilityHint("Select which Claude account to display")
    }

    /// Label for an account: display name if set, otherwise "User N".
    private func accountLabel(_ account: AccountRecord, index: Int) -> String {
        if let name = account.displayName, !name.isEmpty { return name }
        return "User \(index + 1)"
    }
}
