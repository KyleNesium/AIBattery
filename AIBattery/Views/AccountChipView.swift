import SwiftUI

/// The popover's title: a full-width chip naming the active account's provider and
/// identity, which is also the Menu that switches and adds accounts.
///
/// Chip text is `glyph + provider + identity + chevron` — the plan never appears in
/// the chip (it would truncate the identity at 275pt) and lives in the menu rows,
/// which carry the full untruncated identity and plan.
struct AccountChipView: View {
    @ObservedObject var accountStore: AccountStore
    let onAddAccount: (AIProvider) -> Void
    let onSwitchAccount: (String) -> Void

    @AppStorage(UserDefaultsKeys.showFullAccountIdentity) private var showFullAccountIdentity: Bool = false
    @State private var hovered = false

    var body: some View {
        let accounts = accountStore.accounts
        let active = accountStore.activeAccount
        Menu {
            ForEach(AIProvider.allCases, id: \.self) { provider in
                providerSection(provider, accounts: accounts)
            }
        } label: {
            chipLabel(active, accounts: accounts)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(height: Layout.accountChipHeight)
        .background(
            RoundedRectangle(cornerRadius: Layout.bannerCornerRadius)
                .fill(hovered ? ThemeColors.hoverFill : ThemeColors.hoverFill.opacity(ThemeColors.activeLabelOpacity))
        )
        .onHover { hovered = $0 }
        .help(active.map { fullLabel($0, accounts: accounts) } ?? "Switch account")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            active.map {
                Self.accessibilityDescription(
                    for: $0,
                    providerIndex: AccountStore.providerIndex(of: $0, in: accounts),
                    isActive: true,
                    maskEmail: !showFullAccountIdentity
                )
            } ?? "No account selected"
        )
        .accessibilityHint("Opens the account menu to switch or add accounts")
    }

    // MARK: Chip

    private func chipLabel(_ active: AccountRecord?, accounts: [AccountRecord]) -> some View {
        HStack(spacing: Spacing.inner) {
            if let active {
                Text(active.provider.glyph)
                    .font(Typography.bodyLabel)
                    .foregroundStyle(ThemeColors.secondaryLabel)
                Text(active.provider.displayName)
                    .font(Typography.caption)
                    .foregroundStyle(ThemeColors.secondaryLabel)
                    .fixedSize()
                Text(
                    AccountStore.identityLabel(
                        for: active,
                        providerIndex: AccountStore.providerIndex(of: active, in: accounts),
                        maskEmail: !showFullAccountIdentity
                    )
                )
                .font(Typography.buttonLabel)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            } else {
                Text("Account")
                    .font(Typography.buttonLabel)
                    .foregroundStyle(ThemeColors.secondaryLabel)
            }
            Spacer(minLength: Spacing.inner)
            Image(systemName: "chevron.down")
                .font(Typography.chevronIcon)
                .foregroundStyle(ThemeColors.secondaryLabel)
        }
        .padding(.horizontal, Spacing.section)
        .frame(maxWidth: .infinity, minHeight: Layout.accountChipHeight)
        .contentShape(Rectangle())
    }

    // MARK: Menu

    /// One section per provider: its accounts (checkmark on the active one), then
    /// "Add <Provider> Account…" — disabled with the count once the cap is reached.
    /// A provider with no accounts still gets its Add row, under the same header, so
    /// the menu reads the same whether the user has one provider connected or both.
    @ViewBuilder
    private func providerSection(_ provider: AIProvider, accounts: [AccountRecord]) -> some View {
        let rows = AccountStore.displayOrdered(accounts).filter { $0.provider == provider }
        let activeId = accountStore.activeAccountId
        let canAdd = accountStore.canAddAccount(provider: provider)
        Section("\(provider.glyph) \(provider.displayName)") {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, account in
                Button {
                    withAnimation(MotionConstants.standard) { onSwitchAccount(account.id) }
                } label: {
                    if account.id == activeId {
                        Label(rowLabel(account, index: index), systemImage: "checkmark")
                    } else {
                        Text(rowLabel(account, index: index))
                    }
                }
                .accessibilityLabel(
                    Self.accessibilityDescription(for: account, providerIndex: index, isActive: account.id == activeId, maskEmail: !showFullAccountIdentity)
                )
            }
            Button {
                onAddAccount(provider)
            } label: {
                Label(
                    canAdd
                        ? "Add \(provider.displayName) Account…"
                        : "Add \(provider.displayName) Account… (\(rows.count) of \(AccountStore.maxAccountsPerProvider))",
                    systemImage: "plus"
                )
            }
            .disabled(!canAdd)
        }
    }

    /// Menu rows carry the full identity (no masking — this is where the user confirms
    /// *which* account) and the plan; the provider is already the section header.
    private func rowLabel(_ account: AccountRecord, index: Int) -> String {
        AccountStore.displayLabel(for: account, providerIndex: index, showsProviderGlyph: false, includePlan: true, maskEmail: !showFullAccountIdentity)
    }

    private func fullLabel(_ account: AccountRecord, accounts: [AccountRecord]) -> String {
        AccountStore.displayLabel(
            for: account,
            providerIndex: AccountStore.providerIndex(of: account, in: accounts),
            showsProviderGlyph: true,
            includePlan: true,
            maskEmail: !showFullAccountIdentity
        )
    }

    // MARK: Accessibility

    /// One coherent VoiceOver sentence: "Codex account, k•••@example.com, Business, selected".
    nonisolated static func accessibilityDescription(for account: AccountRecord, providerIndex: Int, isActive: Bool, maskEmail: Bool) -> String {
        var parts = [
            "\(account.provider.displayName) account",
            AccountStore.identityLabel(for: account, providerIndex: providerIndex, maskEmail: maskEmail),
        ]
        if account.provider == .codex, let plan = AccountStore.planLabel(account.billingType) {
            parts.append(plan)
        }
        if isActive {
            parts.append("selected")
        }
        return parts.joined(separator: ", ")
    }
}
