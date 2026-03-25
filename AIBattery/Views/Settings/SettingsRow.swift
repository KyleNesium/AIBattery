import SwiftUI

/// Inline settings for account names, refresh rate, and notifications.
struct SettingsRow: View {
    let viewModel: UsageViewModel
    @ObservedObject var accountStore: AccountStore
    let onAddAccount: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Settings")
                .font(Typography.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            // Per-account names
            ForEach(Array(accountStore.accounts.enumerated()), id: \.element.id) { index, account in
                accountNameRow(account, index: index)
            }

            if accountStore.canAddAccount {
                HStack(spacing: 8) {
                    Spacer().frame(width: 50)
                    Button(action: onAddAccount) {
                        HStack(spacing: 3) {
                            Image(systemName: "plus.circle")
                                .font(Typography.tinyLabel)
                            Text("Add Account")
                                .font(Typography.caption)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ThemeColors.action)
                    .accessibilityLabel("Add another Claude account")
                }
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
        return HStack(spacing: 8) {
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
            TextField("User \(index + 1)", text: nameBinding(for: account.id))
                .textFieldStyle(.roundedBorder)
                .font(Typography.caption)
                .help("Display name for this account (max 30 chars)")
            if accountStore.accounts.count > 1 {
                Button(action: {
                    OAuthManager.shared.signOut(accountId: account.id)
                }) {
                    Image(systemName: "xmark.circle")
                        .font(Typography.tinyLabel)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove this account")
                .accessibilityLabel("Remove account \(index + 1)")
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
