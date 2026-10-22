import SwiftUI

/// Popover header: the account chip (provider + identity, also the switch/add menu)
/// and the Settings gear. App name, version and the manual update check live in
/// Settings → About; only the update arrow stays here so an update is discoverable
/// without opening Settings.
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

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.inner) {
            HStack(alignment: .center, spacing: showsBack ? Spacing.xsmall : Spacing.inner) {
                if showsBack {
                    backButton
                        // Arrives from the direction it leads: a short slide in from the
                        // left, so landing on a detail view shows you the way back.
                        .transition(.opacity.combined(with: .offset(x: -MotionConstants.faceShift)))
                }
                AccountChipView(
                    accountStore: accountStore,
                    onAddAccount: onAddAccount,
                    onSwitchAccount: onSwitchAccount
                )
                Spacer(minLength: Spacing.inner)
                if let update = availableUpdate {
                    UpdateArrowButton(update: update)
                        .transition(MotionConstants.expandTransition)
                }
                gearButton
            }
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
    /// The colour the back chevron lights up in: the account you are backing out of.
    private var backTint: Color {
        ThemeColors.providerBadge(accountStore.activeAccount?.provider ?? .claude)
    }

    private var backButton: some View {
        Button(action: onBack) {
            Image(systemName: "chevron.backward")
                .font(Typography.navChevron)
                .foregroundStyle(backHovered ? backTint : ThemeColors.secondaryLabel)
                // Same treatment as the card's drill-in chevron, reversed: it takes the
                // account's colour and glows in it rather than sitting in a box.
                .shadow(color: backTint.opacity(backHovered ? ThemeColors.chevronGlowOpacity : 0), radius: Layout.glowRadius)
                .offset(x: backHovered ? -Layout.chevronHoverShift : 0)
                .frame(width: Layout.backChevronWidth, height: Layout.accountChipHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { backHovered = $0 }
        .animation(MotionConstants.standard, value: backHovered)
        .help("All accounts")
        .accessibilityLabel("Back to all accounts")
        .accessibilityHint("Shows every account at once")
    }

    /// Shared with the overview header so both rows carry the identical control.
    private var gearButton: some View {
        SettingsGearButton(showSettings: $showSettings)
    }

    /// "plus" → "Plus", "api" → "API"; nil for empty/unknown. Forwarder kept for callers/tests.
    nonisolated static func planLabel(_ billingType: String?) -> String? {
        AccountStore.planLabel(billingType)
    }
}
