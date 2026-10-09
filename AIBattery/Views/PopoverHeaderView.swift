import SwiftUI

/// Popover header: the account chip (provider + identity, also the switch/add menu)
/// and the Settings gear. App name, version and the manual update check live in
/// Settings → About; only the *automatic* update-available banner stays here so an
/// update is discoverable without opening Settings.
struct PopoverHeaderView: View {
    @ObservedObject var accountStore: AccountStore
    @Binding var showSettings: Bool
    let onAddAccount: (AIProvider) -> Void
    let onSwitchAccount: (String) -> Void
    let availableUpdate: VersionChecker.UpdateInfo?

    @State private var gearHovered = false
    #if ENABLE_VERSION_CHECKER
    @State private var updateBannerDismissed = false
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.inner) {
            HStack(alignment: .center, spacing: Spacing.inner) {
                AccountChipView(
                    accountStore: accountStore,
                    onAddAccount: onAddAccount,
                    onSwitchAccount: onSwitchAccount
                )
                Spacer(minLength: Spacing.inner)
                gearButton
            }

            #if ENABLE_VERSION_CHECKER
            if let update = availableUpdate, !updateBannerDismissed {
                updateBanner(update)
            }
            #endif
        }
        .padding(.horizontal, Spacing.sectionHorizontal)
        // A touch more air than the 8pt section padding: this is the title row.
        .padding(.vertical, Spacing.medium)
    }

    /// Whether a found-but-dismissed update should badge the gear (Settings → About holds the install action).
    private var gearShowsUpdateBadge: Bool {
        #if ENABLE_VERSION_CHECKER
        return availableUpdate != nil && updateBannerDismissed
        #else
        return false
        #endif
    }

    private var gearButton: some View {
        Button(action: { withAnimation(MotionConstants.standard) { showSettings.toggle() } }) {
            Image(systemName: "gearshape")
                .font(Typography.bodyLabel)
                .frame(width: Layout.accountChipHeight, height: Layout.accountChipHeight)
                .overlay(alignment: .topTrailing) {
                    if gearShowsUpdateBadge {
                        // A symbol, not a bare colored dot: readable without color vision.
                        Image(systemName: "arrow.up.circle.fill")
                            .font(Typography.decorativeIcon)
                            .foregroundStyle(ThemeColors.updateAvailable)
                            .padding(Spacing.tight)
                    }
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(showSettings || gearHovered ? .primary : .secondary)
        .onHover { gearHovered = $0 }
        .help(gearShowsUpdateBadge ? "Settings — update available" : "Settings")
        .accessibilityLabel(gearShowsUpdateBadge ? "Settings, update available" : "Settings")
        .accessibilityHint(showSettings ? "Close settings" : "Open settings")
    }

    #if ENABLE_VERSION_CHECKER
    private func updateBanner(_ update: VersionChecker.UpdateInfo) -> some View {
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
            .accessibilityHint("Opens the release notes in your browser")
            LinkActionButton(
                label: "Install Update",
                icon: "arrow.down.circle",
                size: .compact,
                accessibilityLabel: "Install update version \(update.version)",
                accessibilityHint: "Downloads and installs the update"
            ) {
                AboutSection.installUpdate(update)
            }
            Spacer()
            Button(action: { updateBannerDismissed = true }) {
                Image(systemName: "xmark.circle.fill")
                    .font(Typography.bodyLabel)
                    .foregroundStyle(ThemeColors.secondaryLabel)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
            .accessibilityLabel("Dismiss update banner")
            .accessibilityHint("Hides the banner; the Settings gear keeps an update badge")
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
    }
    #endif

    /// "plus" → "Plus", "api" → "API"; nil for empty/unknown. Forwarder kept for callers/tests.
    nonisolated static func planLabel(_ billingType: String?) -> String? {
        AccountStore.planLabel(billingType)
    }
}
