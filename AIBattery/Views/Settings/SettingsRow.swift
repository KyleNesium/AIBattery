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

            // Per-account names — same order and per-provider numbering as the header chip menu.
            ForEach(Array(AccountStore.displayOrdered(accountStore.accounts).enumerated()), id: \.element.id) { position, account in
                accountNameRow(account, index: AccountStore.providerIndex(of: account, in: accountStore.accounts), isFirst: position == 0)
            }

            // One add link per provider, each gated on its own cap (spec §5:
            // "up to 3 accounts per provider").
            HStack(spacing: Spacing.section) {
                Spacer().frame(width: Layout.settingsLabel)
                if accountStore.canAddAccount(provider: .claude) {
                    LinkActionButton(
                        label: "Add Claude Account…",
                        icon: "plus.circle",
                        help: "Sign in with another Claude account",
                        accessibilityLabel: "Add another Claude account",
                        action: { onAddAccount(.claude) }
                    )
                }
                if accountStore.canAddAccount(provider: .codex) {
                    LinkActionButton(
                        label: "Add Codex Account…",
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
            StyledDivider()
            AboutSection(viewModel: viewModel)
        }
        .padding(.horizontal, Spacing.sectionHorizontal)
        .padding(.vertical, Spacing.section)
    }

    /// Editable name row for a single account.
    private func accountNameRow(_ account: AccountRecord, index: Int, isFirst: Bool) -> some View {
        // One "Accounts" caption for the group (first row only); the badge says which
        // provider each row is and the header chip already says which one is active.
        let label = isFirst ? "Accounts" : ""
        let mixed = AccountStore.spansBothProviders(accountStore.accounts)
        // Placeholder is the row's identity *without* the alias (full, unmasked email or
        // workspace, else "Codex N" + plan) — this is where the user sees which account
        // they are naming, so nothing is hidden here.
        var unaliased = account
        unaliased.displayName = nil
        let placeholder = AccountStore.displayLabel(for: unaliased, providerIndex: index, showsProviderGlyph: false, includePlan: true, maskEmail: false)
        let identity = AccountStore.displayLabel(for: account, providerIndex: index, showsProviderGlyph: mixed, includePlan: true, maskEmail: false)
        return HStack(spacing: Spacing.section) {
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(ThemeColors.secondaryLabel)
                .frame(width: Layout.settingsLabel, alignment: .trailing)
            if mixed {
                ProviderBadge(provider: account.provider)
                    .help("\(account.provider.displayName) account")
                    .accessibilityHidden(false)
                    .accessibilityLabel("\(account.provider.displayName) account")
            }
            AccountNameField(
                accountId: account.id,
                placeholder: placeholder,
                persisted: account.displayName ?? ""
            )
            .accessibilityLabel("Display name for \(identity)")
            if accountStore.accounts.count > 1 {
                Button(action: {
                    let wasActive = accountStore.activeAccountId == account.id
                    OAuthManager.shared.signOut(accountId: account.id)
                    // Removing the ACTIVE account silently repoints `activeAccountId` at
                    // `accounts.first`; without this the view model keeps serving the
                    // removed account's snapshot under the new account's identity.
                    if wasActive {
                        viewModel.syncToActiveAccount()
                    }
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
}

/// The account alias field.
///
/// The text lives in local state and is written back on Enter or when the field loses
/// focus. Binding the field straight to the record persisted the whole `aibattery_accounts`
/// blob and republished `$accounts` on EVERY keystroke, re-rendering the header chip, the
/// popover root and every settings row between characters.
private struct AccountNameField: View {
    let accountId: String
    let placeholder: String
    /// The stored alias. Mirrored into `draft` while the field is not being edited, so a
    /// rename from elsewhere still shows up.
    let persisted: String

    @State private var draft: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $draft)
            .textFieldStyle(.roundedBorder)
            .font(Typography.caption)
            .help("Display name for this account (max 30 chars)")
            .focused($isFocused)
            .onAppear { draft = persisted }
            .onChange(of: persisted) { newValue in
                guard !isFocused else { return }
                draft = newValue
            }
            .onChange(of: isFocused) { focused in
                guard !focused else { return }
                commit()
            }
            .onSubmit { commit() }
    }

    private func commit() {
        let clamped = String(draft.prefix(30))
        if clamped != draft {
            draft = clamped
        }
        guard clamped != persisted else { return }
        OAuthManager.shared.updateAccountMetadata(accountId: accountId, displayName: clamped)
    }
}
