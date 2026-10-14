import SwiftUI

/// One account on the overview: an identity line, one gauge row per quota window, and a
/// state line only when there is something to say. The whole card is one hit target —
/// clicking it makes that account active and opens its detail view.
struct AccountCardView: View {
    let card: AccountCard
    let onSelect: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onSelect) {
            TimelineView(.periodic(from: .now, by: 10)) { context in
                VStack(alignment: .leading, spacing: Spacing.inner) {
                    header
                    ForEach(Array(card.bars.enumerated()), id: \.offset) { _, bar in
                        AccountCardBarRow(bar: bar, now: context.date)
                    }
                    if let text = AccountCard.stateLine(card, now: context.date) {
                        Text(text)
                            .font(Typography.tinyLabel)
                            .foregroundStyle(stateColor)
                    }
                }
                .padding(.horizontal, Spacing.sectionHorizontal)
                .padding(.vertical, Spacing.section)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.accessibilityLabel)
        .accessibilityHint(card.state == .signedOut ? "Signs in to this account" : "Opens this account")
    }

    private var header: some View {
        HStack(spacing: Spacing.xsmall) {
            ProviderBadge(provider: card.provider)
            Text(card.identity)
                .font(Typography.caption)
                .foregroundStyle(hovered || card.isActive ? .primary : ThemeColors.secondaryLabel)
                .lineLimit(1)
                .truncationMode(.middle)
            if let plan = card.plan {
                Text("\u{00B7} \(plan)")
                    .font(Typography.tinyLabel)
                    .foregroundStyle(ThemeColors.tertiaryLabel)
                    .lineLimit(1)
            }
            Spacer(minLength: Spacing.gap)
            if let status = card.status {
                Circle()
                    .fill(ThemeColors.statusColor(status))
                    .frame(width: Layout.dotSizeSmall, height: Layout.dotSizeSmall)
                    .accessibilityHidden(true)
            }
            Text(card.worstPercent.map { "\(Int($0.rounded()))%" } ?? "\u{2014}")
                .font(Typography.monoValueMedium)
                .foregroundStyle(card.worstPercent.map { ThemeColors.barColor(percent: $0) } ?? ThemeColors.tertiaryLabel)
            if card.isActive {
                // A glyph, not just the brighter identity: the active card must be
                // distinguishable without relying on colour or weight alone.
                Text("\u{25B6}")
                    .font(Typography.decorativeIcon)
                    .foregroundStyle(ThemeColors.success)
                    .accessibilityHidden(true)
            }
        }
    }

    private var helpText: String {
        if card.state == .signedOut {
            return "\(card.identity) — signed out. Click to sign in."
        }
        let number = card.worstPercent.map { "worst window \(Int($0.rounded()))%" } ?? "no reading yet"
        return "\(card.identity) — \(number). Click to open."
    }

    private var stateColor: Color {
        switch card.state {
        case .throttled, .limitReached: ThemeColors.danger
        case .signedOut, .timeToLimit, .cached: ThemeColors.caution
        case .fetching, .none: ThemeColors.tertiaryLabel
        }
    }
}

/// label · gauge · tokens · percent, in fixed columns so every card's gauges line up.
struct AccountCardBarRow: View {
    let bar: AccountCard.BarRow
    let now: Date

    var body: some View {
        HStack(spacing: Spacing.gap) {
            Text(bar.uncapped ? "No cap" : bar.label)
                .font(Typography.tinyLabel)
                .foregroundStyle(ThemeColors.secondaryLabel)
                .frame(width: Layout.cardBarLabelWidth, alignment: .trailing)
            GaugeBar(percent: bar.percent ?? 0, barColor: ThemeColors.barColor(percent: bar.percent ?? 0))
            // Tokens spent in the window, same figure the detail bars lead with. The
            // reset moved to the card's state line so this column fits at 275pt.
            Text(bar.tokens.map(TokenFormatter.format) ?? "")
                .font(Typography.monoTiny)
                .foregroundStyle(ThemeColors.tertiaryLabel)
                .frame(width: Layout.cardTokensWidth, alignment: .trailing)
            Text(bar.percent.map { "\(Int($0.rounded()))%" } ?? "\u{2014}")
                .font(Typography.monoTiny)
                .frame(width: Layout.cardPercentWidth, alignment: .trailing)
        }
    }
}
