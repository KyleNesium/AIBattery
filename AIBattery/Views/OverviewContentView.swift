import SwiftUI

/// The popover's overview face: every account at once, one card each. Shown instead of
/// the single-account detail view whenever there are two or more accounts.
///
/// There is no header and no add-account row: a title would restate what the cards
/// already are, and adding an account is something people go to Settings for (which
/// holds the per-provider add links and the cap). The list starts at the top edge and
/// the footer carries Settings.
struct OverviewContentView: View {
    let cards: [AccountCard]
    let onSelect: (AccountCard) -> Void

    /// How often the cards' relative text ("Cached 3m ago", "resets in 2h", the live
    /// dot) is re-read. One `TimelineView` here drives every card; a ticker per card
    /// re-evaluated N whole card bodies every tick for two lines that read the clock.
    static let clockInterval: TimeInterval = 10

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.clockInterval)) { context in
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    if index > 0 {
                        insetDivider
                    }
                    AccountCardView(card: card, now: context.date, onSelect: { onSelect(card) })
                }
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
}

/// The overview's footer. The detail footer's links are all about **one** account —
/// that provider's usage dashboard, that provider's status page, signing that account
/// out — so none of them mean anything on a face that shows every account at once.
/// What is left is what applies to all of them: Settings on the left (labelled, since
/// there is no header to give a bare icon context), how fresh the cards are in the
/// middle, and Quit on the right.
struct OverviewFooterView: View {
    let lastFreshFetch: Date?
    let isLoading: Bool
    var showsUpdateBadge: Bool = false
    @Binding var showSettings: Bool
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: Spacing.medium) {
            SettingsGearButton(
                showSettings: $showSettings,
                showsUpdateBadge: showsUpdateBadge,
                label: "Settings"
            )
            Spacer(minLength: Spacing.inner)
            // Centred: the freshness of what every card above is showing.
            HStack(spacing: Spacing.gap) {
                RefreshButton(action: onRefresh)
                    .help("Refresh every account (R)")
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: Layout.spinnerSize, height: Layout.spinnerSize)
                } else if let lastFreshFetch {
                    TimelineView(.periodic(from: .now, by: 10)) { _ in
                        // Just the elapsed time: "Updated" wrapped to a second line
                        // between Settings and Quit at 275pt, and the refresh icon
                        // beside it already says what the number is.
                        Text(PopoverFooterView.relativeTime(lastFreshFetch))
                            .font(Typography.monoTiny)
                            .foregroundStyle(ThemeColors.tertiaryLabel)
                            .lineLimit(1)
                            .fixedSize()
                            .help("Updated \(PopoverFooterView.relativeTime(lastFreshFetch))")
                            .accessibilityLabel("Updated \(PopoverFooterView.relativeTime(lastFreshFetch))")
                    }
                }
            }
            Spacer(minLength: Spacing.inner)
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
