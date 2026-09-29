import SwiftUI

/// Inline settings for account names, refresh rate, and notifications.
struct SettingsRow: View {
    let viewModel: UsageViewModel
    @ObservedObject var accountStore: AccountStore
    let onAddAccount: (AIProvider) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.gap) {
            Text("Settings")
                .font(Typography.caption)
                .fontWeight(.semibold)
                .foregroundStyle(ThemeColors.secondaryLabel)
                .accessibilityAddTraits(.isHeader)

            // Per-account names — same order and numbering as the header picker.
            ForEach(Array(AccountStore.displayOrdered(accountStore.accounts).enumerated()), id: \.element.id) { index, account in
                accountNameRow(account, index: index)
            }

            // One add link per provider, each gated on its own cap (spec §5:
            // "up to 3 accounts per provider").
            HStack(spacing: Spacing.section) {
                Spacer().frame(width: Layout.settingsLabel)
                if accountStore.canAddAccount(provider: .claude) {
                    LinkActionButton(
                        label: "Add Claude account",
                        icon: "plus.circle",
                        help: "Sign in with another Claude account",
                        accessibilityLabel: "Add another Claude account",
                        action: { onAddAccount(.claude) }
                    )
                }
                if accountStore.canAddAccount(provider: .codex) {
                    LinkActionButton(
                        label: "Add Codex account",
                        icon: "plus.circle",
                        help: "Sign in with a Codex (ChatGPT or OpenAI API key) account",
                        accessibilityLabel: "Add a Codex account",
                        action: { onAddAccount(.codex) }
                    )
                }
                Spacer()
            }
            HStack(spacing: Spacing.section) {
                Spacer().frame(width: Layout.settingsLabel)
                Text("Up to \(AccountStore.maxAccountsPerProvider) accounts per provider.")
                    .font(Typography.tinyLabel)
                    .foregroundStyle(ThemeColors.tertiaryLabel)
            }

            StyledDivider()
            RefreshSettingsSection(viewModel: viewModel)
            StyledDivider()
            DisplaySettingsSection()
            StyledDivider()
            AlertSettingsSection()
            StyledDivider()
            LaunchAtLoginSection()
        }
        .padding(.horizontal, Spacing.sectionHorizontal)
        .padding(.vertical, Spacing.section)
    }

    /// Editable name row for a single account.
    private func accountNameRow(_ account: AccountRecord, index: Int) -> some View {
        let isActive = account.id == accountStore.activeAccountId
        let label = accountStore.accounts.count > 1
            ? (isActive ? "Active" : "Account")
            : "Name"
        let mixed = AccountStore.spansBothProviders(accountStore.accounts)
        // Placeholder mirrors the header picker's label for this row (glyph + "User N" + plan)
        // so a Codex row is identifiable before it has a name.
        let placeholder = AccountStore.displayLabel(
            for: AccountRecord(id: account.id, billingType: account.billingType, addedAt: account.addedAt, provider: account.provider, codexAccessMode: account.codexAccessMode),
            index: index, showsProviderGlyph: false, includePlan: true
        )
        let identity = AccountStore.displayLabel(for: account, index: index, showsProviderGlyph: mixed, includePlan: true)
        return HStack(spacing: Spacing.section) {
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(ThemeColors.secondaryLabel)
                .frame(width: Layout.settingsLabel, alignment: .trailing)
            if mixed {
                Text(account.provider.glyph)
                    .font(Typography.caption)
                    .foregroundStyle(ThemeColors.secondaryLabel)
                    .help("\(account.provider.displayName) account")
                    .accessibilityLabel("\(account.provider.displayName) account")
            }
            TextField(placeholder, text: nameBinding(for: account.id))
                .textFieldStyle(.roundedBorder)
                .font(Typography.caption)
                .help("Display name for this account (max 30 chars)")
                .accessibilityLabel("Display name for \(identity)")
            if accountStore.accounts.count > 1 {
                Button(action: {
                    OAuthManager.shared.signOut(accountId: account.id)
                }) {
                    Image(systemName: "xmark.circle")
                        .font(Typography.tinyLabel)
                        .foregroundStyle(ThemeColors.secondaryLabel)
                }
                .buttonStyle(.plain)
                .help("Remove \(identity)")
                .accessibilityLabel("Remove \(identity)")
                .accessibilityHint("Signs out and removes this account")
            }
        }
    }

    /// Two-way binding that reads/writes `displayName` on the AccountRecord.
    private func nameBinding(for accountId: String) -> Binding<String> {
        Binding(
            get: {
                accountStore.accounts.first { $0.id == accountId }?.displayName ?? ""
            },
            set: { newValue in
                let clamped = String(newValue.prefix(30))
                OAuthManager.shared.updateAccountMetadata(
                    accountId: accountId,
                    displayName: clamped
                )
            }
        )
    }
}
