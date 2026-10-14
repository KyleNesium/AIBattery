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
                insetDivider
                AccountCardView(card: card, onSelect: { onSelect(card) })
            }
            if canAddClaude || canAddCodex {
                insetDivider
                addRow
            }
        }
    }

    /// Title and gear, nothing else. A summary line here competed with the cards for
    /// the same facts; the cards are the content.
    private var header: some View {
        HStack(spacing: Spacing.gap) {
            Text("Accounts")
                .font(Typography.accountTitle)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            SettingsGearButton(showSettings: $showSettings, showsUpdateBadge: showsUpdateBadge)
        }
        .padding(.horizontal, Spacing.sectionHorizontal)
        .padding(.vertical, Spacing.section)
    }

    /// Indented to the content gutter so the rows read as one list rather than a stack
    /// of separate panels.
    private var insetDivider: some View {
        StyledDivider()
            .padding(.leading, Spacing.sectionHorizontal)
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

/// The overview's footer. The detail footer's links are all about **one** account —
/// that provider's usage dashboard, that provider's status page, signing that account
/// out — so none of them mean anything on a face that shows every account at once.
/// What is left is the two things that apply to all of them: refresh and quit.
struct OverviewFooterView: View {
    let lastFreshFetch: Date?
    let isLoading: Bool
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: Spacing.medium) {
            RefreshButton(action: onRefresh)
                .help("Refresh every account (R)")
            if isLoading {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: Layout.spinnerSize, height: Layout.spinnerSize)
            } else if let lastFreshFetch {
                TimelineView(.periodic(from: .now, by: 10)) { _ in
                    Text("Updated \(PopoverFooterView.relativeTime(lastFreshFetch))")
                        .font(Typography.monoTiny)
                        .foregroundStyle(ThemeColors.tertiaryLabel)
                }
            }
            Spacer()
            FooterLink(
                icon: "xmark.circle",
                label: "Quit",
                tooltip: "Quit (\u{2318}Q)",
                accessibilityLabel: "Quit AI Battery",
                accessibilityHint: "Quit application",
                showsExternalArrow: false
            ) {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, Spacing.sectionHorizontal)
        .padding(.vertical, Spacing.section)
    }
}
