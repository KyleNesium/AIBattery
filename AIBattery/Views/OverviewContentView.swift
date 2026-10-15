import SwiftUI

/// The popover's overview face: every account at once, one card each. Shown instead of
/// the single-account detail view whenever there are two or more accounts.
///
/// There is no header. A title row would spend ~44pt restating what the cards already
/// are, so the list starts at the top edge and Settings lives in the footer.
struct OverviewContentView: View {
    let cards: [AccountCard]
    let canAddClaude: Bool
    let canAddCodex: Bool
    let onSelect: (AccountCard) -> Void
    let onAdd: (AIProvider) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                if index > 0 {
                    insetDivider
                }
                AccountCardView(card: card, onSelect: { onSelect(card) })
            }
            if canAddClaude || canAddCodex {
                insetDivider
                addRow
            }
        }
        .padding(.top, Spacing.gap)
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
/// What is left is what applies to all of them: refresh, Settings and quit. The gear
/// lives here because the overview has no header to hold it.
struct OverviewFooterView: View {
    let lastFreshFetch: Date?
    let isLoading: Bool
    var showsUpdateBadge: Bool = false
    @Binding var showSettings: Bool
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
            SettingsGearButton(showSettings: $showSettings, showsUpdateBadge: showsUpdateBadge)
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
        .padding(.vertical, Spacing.small)
    }
}
