import SwiftUI

/// One account on the overview: an identity line, one gauge row per quota window, and a
/// state line only when there is something to say.
///
/// The whole card is one hit target that opens that account. Three things say so: the
/// row lifts on hover, a chevron sits at the trailing edge, and the identity brightens —
/// the same vocabulary as a list row that drills down.
struct AccountCardView: View {
    let card: AccountCard
    let onSelect: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onSelect) {
            TimelineView(.periodic(from: .now, by: 10)) { context in
                HStack(alignment: .center, spacing: Spacing.gap) {
                    VStack(alignment: .leading, spacing: Spacing.inner) {
                        header(now: context.date)
                        ForEach(Array(card.bars.enumerated()), id: \.offset) { _, bar in
                            AccountCardBarRow(bar: bar)
                        }
                        if let text = AccountCard.stateLine(card, now: context.date) {
                            Text(text)
                                .font(Typography.tinyLabel)
                                .foregroundStyle(stateColor)
                        }
                    }
                    // Drill-in affordance, the mirror of the detail header's back control:
                    // on hover it gains the same rounded fill and slides toward where it
                    // leads. Motion says "this goes somewhere" far better than a glyph.
                    Image(systemName: "chevron.forward")
                        .font(Typography.navChevron)
                        .foregroundStyle(hovered ? .primary : ThemeColors.tertiaryLabel)
                        .offset(x: hovered ? Layout.chevronHoverShift : 0)
                        .frame(width: Layout.chevronHitSize, height: Layout.chevronHitSize)
                        .background {
                            RoundedRectangle(cornerRadius: Layout.smallCornerRadius)
                                .fill(hovered ? ThemeColors.hoverFill : .clear)
                                .overlay {
                                    RoundedRectangle(cornerRadius: Layout.smallCornerRadius)
                                        .strokeBorder(hovered ? ThemeColors.hoverStroke : .clear, lineWidth: Layout.subtleBorderWidth)
                                }
                        }
                        .animation(MotionConstants.standard, value: hovered)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, Spacing.gap)
                .padding(.vertical, Spacing.section)
                .background(rowHighlight)
                // The highlight is inset from the panel edge; the content still lines up
                // with the header and footer gutters.
                .padding(.horizontal, Spacing.medium)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(helpText)
        .accessibilityElement(children: .ignore)
        // `children: .ignore` replaces the Button's own representation, which drops the
        // button trait with it — the card then exposed no actionable element at all to
        // VoiceOver or to automation. Put the trait back explicitly.
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(card.accessibilityLabel)
        // The state line ("Throttled", "~2h to limit · resets in 3d", "Cached 3m ago") is
        // the card's value. `children: .ignore` hides the on-screen Text from VoiceOver,
        // so without this a screen-reader user got no state at all.
        .accessibilityValue(AccountCard.stateLine(card, now: Date()) ?? "")
        .accessibilityHint(card.state == .signedOut ? "Signs in to this account" : "Opens this account")
    }

    /// A transient provider-tinted wash for the row under the pointer.
    private var rowHighlight: some View {
        hoverShape
            .animation(MotionConstants.standard, value: hovered)
    }

    private var tint: Color { ThemeColors.providerBadge(card.provider) }

    private var hoverShape: some View {
        let fill: Color = tint.opacity(hovered ? ThemeColors.rowHoverTintOpacity : 0)
        let stroke: Color = tint.opacity(hovered ? ThemeColors.rowHoverStrokeOpacity : 0)
        return RoundedRectangle(cornerRadius: Layout.bannerCornerRadius)
            .fill(fill)
            // The fill alone is a blob; the hairline is what gives it an edge.
            .overlay {
                RoundedRectangle(cornerRadius: Layout.bannerCornerRadius)
                    .strokeBorder(stroke, lineWidth: Layout.subtleBorderWidth)
            }
    }

    private func header(now: Date) -> some View {
        HStack(spacing: Spacing.xsmall) {
            ProviderBadge(provider: card.provider)
            Text(card.identity)
                .font(Typography.accountTitle)
                .foregroundStyle(hovered || card.isActive ? .primary : ThemeColors.secondaryLabel)
                .lineLimit(1)
                .truncationMode(.middle)
                // The name is the row; the badge and the plan yield before it does.
                .layoutPriority(1)
            if AccountCard.isLive(lastActivity: card.lastActivity, now: now) {
                // Breathes only while the provider is actually being used.
                LiveDot(color: tint)
                    .padding(.leading, Spacing.tight)
            }
            if card.isActive {
                // A word in the app's existing badge vocabulary, not a glyph crammed
                // against the percentage — and readable without colour vision.
                Text("active")
                    .font(Typography.badgeLabel)
                    .foregroundStyle(ThemeColors.secondaryLabel)
                    .padding(.horizontal, Spacing.small)
                    .padding(.vertical, Spacing.micro)
                    .background(ThemeColors.badgeFill, in: RoundedRectangle(cornerRadius: Layout.barCornerRadius))
                    .accessibilityHidden(true)
            }
            if let plan = card.plan {
                Text("\u{00B7} \(plan)")
                    .font(Typography.tinyLabel)
                    .foregroundStyle(ThemeColors.tertiaryLabel)
                    .lineLimit(1)
                    .layoutPriority(-1)
            }
            Spacer(minLength: Spacing.inner)
            if let status = card.status {
                Circle()
                    .fill(ThemeColors.statusColor(status))
                    .frame(width: Layout.dotSizeSmall, height: Layout.dotSizeSmall)
                    .accessibilityHidden(true)
            }
            Text(card.worstPercent.map { "\(Int($0.rounded()))%" } ?? "\u{2014}")
                .font(Typography.monoValueMedium)
                .foregroundStyle(card.worstPercent.map { ThemeColors.barColor(percent: $0) } ?? ThemeColors.tertiaryLabel)
        }
    }

    private var helpText: String {
        if card.state == .signedOut {
            return "\(card.identity) — signed out. Click to sign in."
        }
        let number = card.worstPercent.map { "worst window \(Int($0.rounded()))%" } ?? "no reading yet"
        return "\(card.identity) — \(number). Click to open this account."
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

    var body: some View {
        HStack(spacing: Spacing.gap) {
            Text(bar.uncapped ? "No cap" : bar.label)
                .font(Typography.tinyLabel)
                .foregroundStyle(ThemeColors.secondaryLabel)
                .frame(width: Layout.cardBarLabelWidth, alignment: .trailing)
            GaugeBar(percent: bar.percent ?? 0, barColor: ThemeColors.barColor(percent: bar.percent ?? 0))
            // Tokens spent in the window, the same figure the detail bars lead with. The
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
