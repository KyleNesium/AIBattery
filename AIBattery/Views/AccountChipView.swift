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
        HStack(spacing: Spacing.gap) {
            if let active {
                let identity = AccountStore.identityLabel(
                    for: active,
                    providerIndex: AccountStore.providerIndex(of: active, in: accounts),
                    maskEmail: !showFullAccountIdentity
                )
                ProviderBadge(provider: active.provider)
                if Self.showsProviderName(identity: identity, provider: active.provider) {
                    Text(active.provider.displayName)
                        .font(Typography.caption)
                        .foregroundStyle(hovered ? .primary : ThemeColors.secondaryLabel)
                        .fixedSize()
                }
                Text(identity)
                    .font(Typography.sectionHeader)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("Account")
                    .font(Typography.sectionHeader)
                    .foregroundStyle(ThemeColors.secondaryLabel)
            }
            Image(systemName: "chevron.down")
                .font(Typography.chevronIcon)
                .foregroundStyle(hovered ? .primary : ThemeColors.secondaryLabel)
        }
        // No inner inset: with no pill there is nothing to inset from, and the badge
        // now sits flush with the section content edge below it (the dropped menu's
        // left edge, at the anchor's x = 0, lines up with the badge too).
    }

    /// False when the identity already *starts with* the provider name as a word —
    /// an alias "Codex", the fallback "Claude 1", a workspace named "Claude Team" —
    /// which would otherwise read "Claude  Claude Team". Only a whole leading word
    /// counts: "Claudette" or "claude@x.io" still get the caption.
    nonisolated static func showsProviderName(identity: String, provider: AIProvider) -> Bool {
        let firstWord = identity.trimmingCharacters(in: .whitespaces)
            .split(maxSplits: 1, whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        return firstWord.caseInsensitiveCompare(provider.displayName) != .orderedSame
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
        .foregroundStyle(.white)
        .frame(width: Layout.providerBadgeSize, height: Layout.providerBadgeSize)
        .background(
            RoundedRectangle(cornerRadius: Layout.tabCornerRadius, style: .continuous)
                .fill(ThemeColors.providerBadge(provider))
        )
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
