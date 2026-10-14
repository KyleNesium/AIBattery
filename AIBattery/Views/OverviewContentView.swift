import SwiftUI

/// The popover's overview face: every account at once, one card each. Shown instead of
/// the single-account detail view whenever there are two or more accounts.
struct OverviewContentView: View {
    let cards: [AccountCard]
    let canAddClaude: Bool
    let canAddCodex: Bool
    var showsUpdateBadge: Bool = false
    @Binding var showSettings: Bool
    let onSelect: (AccountCard) -> Void
    let onAdd: (AIProvider) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ForEach(cards) { card in
                StyledDivider()
                AccountCardView(card: card, onSelect: { onSelect(card) })
            }
            if canAddClaude || canAddCodex {
                StyledDivider()
                addRow
            }
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.gap) {
            Text("Accounts")
                .font(Typography.accountTitle)
                .accessibilityAddTraits(.isHeader)
            Text("\(cards.count)")
                .font(Typography.monoCaption)
                .foregroundStyle(ThemeColors.secondaryLabel)
                .accessibilityHidden(true)
            Spacer()
            SettingsGearButton(showSettings: $showSettings, showsUpdateBadge: showsUpdateBadge)
        }
        .padding(.horizontal, Spacing.sectionHorizontal)
        .padding(.vertical, Spacing.section)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(cards.count) accounts")
    }

    private var addRow: some View {
        HStack {
            LinkActionButton(
                label: "Add account\u{2026}",
                icon: "plus.circle",
                help: canAddClaude && canAddCodex
                    ? "Sign in with another Claude or Codex account"
                    : (canAddClaude ? "Sign in with another Claude account" : "Sign in with another Codex account"),
                accessibilityLabel: "Add another account",
                accessibilityHint: "Opens the sign-in screen"
            ) {
                // Claude first when both have room — the sign-in screen's own picker
                // switches providers, so this only decides the starting tab.
                onAdd(canAddClaude ? .claude : .codex)
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.sectionHorizontal)
        .padding(.vertical, Spacing.section)
    }
}
