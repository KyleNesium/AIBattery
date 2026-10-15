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
    /// Shown when there is an overview to go back to (two or more accounts).
    var showsBack: Bool = false
    var onBack: () -> Void = {}

    @State private var backHovered = false

    #if ENABLE_VERSION_CHECKER
    @State private var updateBannerDismissed = false
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.inner) {
            HStack(alignment: .center, spacing: showsBack ? Spacing.xsmall : Spacing.inner) {
                if showsBack {
                    backButton
                }
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
        .padding(.vertical, Spacing.section)
    }

    /// Whether the detail view has an overview to return to. The overview only exists
    /// with two or more accounts, so a single-account popover never shows the chevron.
    nonisolated static func showsBack(eligibleAccountCount: Int) -> Bool {
        eligibleAccountCount >= 2
    }

    /// Mirrors the overview card's drill-in chevron — same glyph family, same size,
    /// sliding the same couple of points but the other way, so going in and coming back
    /// read as one gesture reversed. The rounded hover fill is what says "control";
    /// at rest it is just a quiet chevron beside the title.
    private var backButton: some View {
        Button(action: onBack) {
            Image(systemName: "chevron.backward")
                .font(Typography.navChevron)
                .offset(x: backHovered ? -Layout.chevronHoverShift : 0)
                .frame(width: Layout.backChevronWidth, height: Layout.backChevronWidth)
                .background {
                    // Chrome, not content: a neutral fill with the same hairline edge the
                    // account rows get, so every highlight in the popover is built the
                    // same way — only the tint says whether it belongs to an account.
                    RoundedRectangle(cornerRadius: Layout.smallCornerRadius)
                        .fill(backHovered ? ThemeColors.hoverFill : .clear)
                        .overlay {
                            RoundedRectangle(cornerRadius: Layout.smallCornerRadius)
                                .strokeBorder(
                                    backHovered ? ThemeColors.hoverStroke : .clear,
                                    lineWidth: Layout.subtleBorderWidth
                                )
                        }
                }
                .frame(height: Layout.accountChipHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(backHovered ? .primary : ThemeColors.secondaryLabel)
        .onHover { backHovered = $0 }
        .animation(MotionConstants.standard, value: backHovered)
        .help("All accounts")
        .accessibilityLabel("Back to all accounts")
        .accessibilityHint("Shows every account at once")
    }

    /// Whether a found-but-dismissed update should badge the gear (Settings → About holds the install action).
    private var gearShowsUpdateBadge: Bool {
        #if ENABLE_VERSION_CHECKER
        return availableUpdate != nil && updateBannerDismissed
        #else
        return false
        #endif
    }

    /// Shared with the overview header so both rows carry the identical control.
    private var gearButton: some View {
        SettingsGearButton(showSettings: $showSettings, showsUpdateBadge: gearShowsUpdateBadge)
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
