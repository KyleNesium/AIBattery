import Foundation
import Testing
@testable import AIBatteryCore

/// The "Show account email" toggle answers one question — "which account is
/// this?" — and an alias is what usually stands in the way of answering it. The reveal
/// lives in `displayLabel` (menu rows, Settings) and deliberately **not** in
/// `identityLabel`, which feeds the 275pt overview card and header chip.
@Suite("AccountStore hidden identity")
struct AccountStoreHiddenIdentityTests {
    private func account(
        id: String = "a1",
        displayName: String? = nil,
        provider: AIProvider = .codex,
        discoveredIdentity: String? = nil
    ) -> AccountRecord {
        AccountRecord(
            id: id,
            displayName: displayName,
            addedAt: Date(),
            provider: provider,
            discoveredIdentity: discoveredIdentity
        )
    }

    // MARK: hiddenIdentity

    @Test func hiddenIdentity_isTheIdentityAnAliasCovers() {
        let record = account(displayName: "API Rates", discoveredIdentity: "kyle@example.com")
        #expect(AccountStore.hiddenIdentity(for: record) == "kyle@example.com")
    }

    /// Without an alias the identity is already the label, so nothing is hidden.
    @Test func hiddenIdentity_isNilWithoutAnAlias() {
        #expect(AccountStore.hiddenIdentity(for: account(discoveredIdentity: "kyle@example.com")) == nil)
    }

    /// A whitespace-only alias doesn't outrank anything in `identityLabel`, so it isn't
    /// covering the identity either.
    @Test func hiddenIdentity_ignoresABlankAlias() {
        #expect(AccountStore.hiddenIdentity(for: account(displayName: "   ", discoveredIdentity: "kyle@example.com")) == nil)
    }

    @Test func hiddenIdentity_isNilWhenTheProviderNamedNothing() {
        #expect(AccountStore.hiddenIdentity(for: account(displayName: "Mine")) == nil)
    }

    /// Revealing an alias that is already the identity would print the same string twice.
    @Test func hiddenIdentity_isNilWhenTheAliasIsTheIdentity() {
        let record = account(displayName: "kyle@example.com", discoveredIdentity: "kyle@example.com")
        #expect(AccountStore.hiddenIdentity(for: record) == nil)
    }

    /// Claude's discovered identity is a workspace name rather than an email — nothing to
    /// *mask*, but still the answer to "which account is this?" when an alias covers it.
    @Test func hiddenIdentity_coversAClaudeWorkspaceToo() {
        let record = account(displayName: "Work", provider: .claude, discoveredIdentity: "Ringier Workspace")
        #expect(AccountStore.hiddenIdentity(for: record) == "Ringier Workspace")
    }

    // MARK: displayLabel reveals it

    @Test func displayLabel_appendsTheHiddenIdentityWhenUnmasked() {
        let record = account(displayName: "API Rates", discoveredIdentity: "kyle@example.com")
        #expect(
            AccountStore.displayLabel(
                for: record, providerIndex: 0, showsProviderGlyph: false, includePlan: false, maskEmail: false
            ) == "API Rates (kyle@example.com)"
        )
    }

    @Test func displayLabel_keepsTheAliasAloneWhenMasked() {
        let record = account(displayName: "API Rates", discoveredIdentity: "kyle@example.com")
        #expect(
            AccountStore.displayLabel(
                for: record, providerIndex: 0, showsProviderGlyph: false, includePlan: false, maskEmail: true
            ) == "API Rates"
        )
    }

    /// The plan stays last, so the suffix order reads name → who → plan.
    @Test func displayLabel_putsTheIdentityBeforeThePlan() {
        var record = account(displayName: "API Rates", discoveredIdentity: "kyle@example.com")
        record.billingType = "plus"
        #expect(
            AccountStore.displayLabel(
                for: record, providerIndex: 0, showsProviderGlyph: false, includePlan: true, maskEmail: false
            ) == "API Rates (kyle@example.com) · Plus"
        )
    }

    /// Revealing never masks: a masked address beside a name answers nothing.
    @Test func displayLabel_revealsTheAddressInFull() {
        let record = account(displayName: "Work", discoveredIdentity: "kyle@example.com")
        let label = AccountStore.displayLabel(
            for: record, providerIndex: 0, showsProviderGlyph: false, includePlan: false, maskEmail: false
        )
        #expect(!label.contains("•"))
    }

    /// An unaliased account already shows its identity; it must not be printed twice.
    @Test func displayLabel_doesNotDoubleUpWithoutAnAlias() {
        let record = account(discoveredIdentity: "kyle@example.com")
        #expect(
            AccountStore.displayLabel(
                for: record, providerIndex: 0, showsProviderGlyph: false, includePlan: false, maskEmail: false
            ) == "kyle@example.com"
        )
    }

    // MARK: the card and chip are left alone

    /// `identityLabel` feeds the 275pt overview card and the header chip, where an
    /// appended address truncated mid-domain. It stays the alias, both ways.
    @Test func identityLabel_isUnchangedByTheReveal() {
        let record = account(displayName: "API Rates", discoveredIdentity: "kyle@example.com")
        #expect(AccountStore.identityLabel(for: record, providerIndex: 0, maskEmail: false) == "API Rates")
        #expect(AccountStore.identityLabel(for: record, providerIndex: 0, maskEmail: true) == "API Rates")
    }

    // MARK: menu rows carry it

    @Test func menuRow_showsTheIdentityBehindTheAlias() {
        let accounts = [account(displayName: "API Rates", discoveredIdentity: "kyle@example.com")]
        let sections = AccountChipView.menuModel(accounts: accounts, activeId: "a1", maskEmail: false)
        let titles = sections.flatMap { $0.rows.map(\.title) }
        #expect(titles == ["API Rates (kyle@example.com)"])
    }

    @Test func menuRow_hidesItWhenMasked() {
        let accounts = [account(displayName: "API Rates", discoveredIdentity: "kyle@example.com")]
        let sections = AccountChipView.menuModel(accounts: accounts, activeId: "a1", maskEmail: true)
        let titles = sections.flatMap { $0.rows.map(\.title) }
        #expect(titles == ["API Rates"])
    }

    @Test func voiceOver_speaksTheIdentityBehindTheAlias() {
        let record = account(displayName: "API Rates", discoveredIdentity: "kyle@example.com")
        let spoken = AccountChipView.accessibilityDescription(
            for: record, providerIndex: 0, isActive: true, maskEmail: false
        )
        #expect(spoken == "Codex account, API Rates, kyle@example.com, selected")
    }
}
