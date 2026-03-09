import SwiftUI

/// Inline settings for account names, refresh rate, and notifications.
struct SettingsRow: View {
    let viewModel: UsageViewModel
    @ObservedObject var accountStore: AccountStore
    let onAddAccount: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Settings")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

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
                                .font(.system(size: 10))
                            Text("Add Account")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .accessibilityLabel("Add another Claude account")
                }
            }

            RefreshSettingsSection(viewModel: viewModel)
            DisplaySettingsSection()
            AlertSettingsSection()
            LaunchAtLoginSection()

            // Global hotkey display
            HStack(spacing: 8) {
                Text("Hotkey")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
                Text("⌥⇧B")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.06))
                    )
                Text("Toggle popover")
                    .font(.caption2)
                    .foregroundStyle(ThemeColors.tertiaryLabel)
                Spacer()
            }
            .accessibilityLabel("Global hotkey: Option Shift B to toggle popover")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Editable name row for a single account.
    private func accountNameRow(_ account: AccountRecord, index: Int) -> some View {
        let isActive = account.id == accountStore.activeAccountId
        let label = accountStore.accounts.count > 1
            ? (isActive ? "Active" : "Account")
            : "Name"
        return HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
            TextField("Account \(index + 1)", text: nameBinding(for: account.id))
                .textFieldStyle(.roundedBorder)
                .font(.caption)
            if accountStore.accounts.count > 1 {
                Button(action: {
                    OAuthManager.shared.signOut(accountId: account.id)
                }) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 10))
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
