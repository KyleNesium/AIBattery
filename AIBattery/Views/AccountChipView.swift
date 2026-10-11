import AppKit
import SwiftUI

/// The popover's title: a compact chip — provider badge + account identity + chevron —
/// that hugs its content (not the whole header row). Clicking it pops an AppKit
/// `NSMenu` (switch / add accounts) anchored below the chip.
///
/// Why AppKit: SwiftUI's `Menu` on macOS sizes its label to the control's intrinsic
/// width and clips the rest, and an overlaid transparent-label `Menu` has no hit
/// area. A plain `Button` + `NSMenu.popUp` gives a chip we fully draw, a reliable
/// hit target, native section headers and checkmarks.
///
/// The plan never appears in the chip (it would truncate the identity at 275pt);
/// it lives in the menu rows.
struct AccountChipView: View {
    @ObservedObject var accountStore: AccountStore
    let onAddAccount: (AIProvider) -> Void
    let onSwitchAccount: (String) -> Void

    @AppStorage(UserDefaultsKeys.showFullAccountIdentity) private var showFullAccountIdentity: Bool = false
    @State private var hovered = false
    @State private var anchor = MenuAnchor()

    var body: some View {
        let accounts = accountStore.accounts
        let active = accountStore.activeAccount
        Button(action: presentMenu) {
            chipFace(active, accounts: accounts)
                .frame(height: Layout.accountChipHeight)
                // No pill: a filled box on the popover backdrop read as a foreign
                // control (a flat lighter rectangle under the title). The chip uses
                // the same language as the gear next to it — nothing at rest, the
                // secondary parts (provider caption, chevron) brighten to primary on
                // hover and while the menu is open — so the header stays a title.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(MenuAnchorView(anchor: anchor))
        .onHover { hovered = $0 }
        .help(active.map { fullLabel($0, accounts: accounts) } ?? "Switch account")
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

    // MARK: Chip face

    private func chipFace(_ active: AccountRecord?, accounts: [AccountRecord]) -> some View {
        // Three quiet elements, like a document title with a logo: the brand mark in
        // its own colour says which provider (no "Claude" / "Codex" caption — it
        // doubled the mark and often the identity itself), the identity is the title,
        // and a small chevron is the only hint that it's a control. Hovering (or the
        // open menu) lifts the chevron from secondary to primary; nothing else moves.
        // One tight cluster: mark · 6pt · name · 3pt · chevron, all centred on the
        // text's cap height (`firstTextBaseline` alignment + each glyph's own baseline
        // offset) rather than on the 28pt row, so the mark no longer sits a hair high.
        // The chevron hugs the name (a wider gap left it floating, orphaned between name
        // and gear) and is a plain `chevron.down` — the up/down pop-up pair read as a
        // separate widget.
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if let active {
                ProviderBadge(provider: active.provider)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + Layout.capHeightBaselineOffset }
                Text(AccountStore.identityLabel(
                    for: active,
                    providerIndex: AccountStore.providerIndex(of: active, in: accounts),
                    maskEmail: !showFullAccountIdentity
                ))
                .font(Typography.accountTitle)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.leading, Layout.accountChipSpacing)
            } else {
                Text("Account")
                    .font(Typography.accountTitle)
                    .foregroundStyle(ThemeColors.secondaryLabel)
            }
            Image(systemName: "chevron.down")
                .font(Typography.switcherChevron)
                .foregroundStyle(hovered ? .primary : ThemeColors.secondaryLabel)
                .padding(.leading, Spacing.xsmall)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + Layout.capHeightBaselineOffset }
        }
        // No inner inset: the mark sits flush with the section content edge below it,
        // and the dropped menu's left edge (the anchor's x = 0) lines up with it.
    }

    // MARK: Menu model (pure, tested)

    struct MenuRow: Equatable {
        let id: String
        let title: String
        let isActive: Bool
        let accessibilityLabel: String
    }

    struct MenuSection: Equatable {
        let provider: AIProvider
        let rows: [MenuRow]
        let canAdd: Bool
        var addTitle: String {
            canAdd
                ? "Add \(provider.displayName) Account…"
                : "Add \(provider.displayName) Account… (\(rows.count) of \(AccountStore.maxAccountsPerProvider))"
        }
    }

    /// One section per provider (always both, so the menu reads the same with one or
    /// two providers connected): rows in `displayOrdered` order with the identity
    /// (masked per the Display toggle) and plan, the active row checked, then an Add
    /// row that is disabled with the count once the per-provider cap is reached.
    nonisolated static func menuModel(accounts: [AccountRecord], activeId: String?, maskEmail: Bool) -> [MenuSection] {
        let ordered = AccountStore.displayOrdered(accounts)
        return AIProvider.allCases.map { provider in
            let rows = ordered.filter { $0.provider == provider }
            return MenuSection(
                provider: provider,
                rows: rows.enumerated().map { index, account in
                    MenuRow(
                        id: account.id,
                        title: AccountStore.displayLabel(for: account, providerIndex: index, showsProviderGlyph: false, includePlan: true, maskEmail: maskEmail),
                        isActive: account.id == activeId,
                        accessibilityLabel: accessibilityDescription(for: account, providerIndex: index, isActive: account.id == activeId, maskEmail: maskEmail)
                    )
                },
                canAdd: rows.count < AccountStore.maxAccountsPerProvider
            )
        }
    }

    // MARK: AppKit menu

    private func presentMenu() {
        guard let view = anchor.view else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let sections = Self.menuModel(accounts: accountStore.accounts, activeId: accountStore.activeAccountId, maskEmail: !showFullAccountIdentity)
        for (index, section) in sections.enumerated() {
            if index > 0 {
                menu.addItem(.separator())
            }
            menu.addItem(Self.header(section.provider.displayName))
            for row in section.rows {
                let item = ClosureMenuItem(title: row.title) {
                    withAnimation(MotionConstants.standard) { onSwitchAccount(row.id) }
                }
                item.state = row.isActive ? .on : .off
                item.setAccessibilityLabel(row.accessibilityLabel)
                menu.addItem(item)
            }
            let add = ClosureMenuItem(title: section.addTitle) { onAddAccount(section.provider) }
            add.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
            add.isEnabled = section.canAdd
            menu.addItem(add)
        }
        // Drop the menu just below the chip, left-aligned with it. The anchor NSView is
        // NOT flipped (origin bottom-left), so "below the bottom edge" is a negative y;
        // `popUp` puts the menu's top-left corner at the given point.
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -Spacing.tight), in: view)
        // `popUp` runs the menu's tracking loop synchronously; SwiftUI misses the
        // mouse-exit that happens while it runs, so the hover pill would stick.
        hovered = false
    }

    private static func header(_ title: String) -> NSMenuItem {
        if #available(macOS 14.0, *) {
            return NSMenuItem.sectionHeader(title: title)
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
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

    private func fullLabel(_ account: AccountRecord, accounts: [AccountRecord]) -> String {
        AccountStore.displayLabel(
            for: account,
            providerIndex: AccountStore.providerIndex(of: account, in: accounts),
            showsProviderGlyph: true,
            includePlan: true,
            maskEmail: !showFullAccountIdentity
        )
    }
}

/// Rounded-square tinted badge with the provider's real brand mark in white
/// (`AIProvider.markImage`, bundled SVG) — the kind of mark macOS uses for
/// accounts in System Settings. The name sits next to it, so the tint is a
/// recognition aid, never the only signal.
struct ProviderBadge: View {
    let provider: AIProvider

    var body: some View {
        Group {
            if let mark = provider.markImage {
                Image(nsImage: mark)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: Layout.providerMarkSize, height: Layout.providerMarkSize)
            } else {
                Image(systemName: provider.symbolName)
                    .font(Typography.badgeSymbol)
            }
        }
        // Bare mark in the provider's colour — no filled square. The tinted tile was
        // the one saturated block in an otherwise monochrome header and made the chip
        // read as a foreign control; a logo-style mark reads as part of the title.
        .foregroundStyle(ThemeColors.providerBadge(provider))
        .frame(width: Layout.providerBadgeSize, height: Layout.providerBadgeSize)
        .accessibilityHidden(true)
    }
}

// MARK: - AppKit plumbing

/// `NSMenuItem` whose action is a Swift closure (target is the item itself).
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("not used")
    }

    @objc private func fire() {
        handler()
    }
}

/// Holds the AppKit view the menu is positioned against. A class so the SwiftUI
/// `@State` can hand the representable a stable box to write into.
@MainActor
private final class MenuAnchor {
    weak var view: NSView?
}

/// Zero-cost invisible view that reports its `NSView` to `MenuAnchor` — the chip's
/// `.background` so it shares the chip's frame.
private struct MenuAnchorView: NSViewRepresentable {
    let anchor: MenuAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }
}
