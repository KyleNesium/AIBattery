import Foundation
import Testing
@testable import AIBatteryCore

/// The Display toggle answers one question — "which account is this?" — and
/// `hasRevealableIdentity` decides whether Settings offers it at all. It must stay
/// visible wherever there is an identity to show (masked email, or one an alias is
/// covering) and disappear only when there is genuinely nothing behind it.
@Suite("AccountStore identity reveal")
struct AccountStoreRevealableIdentityTests {
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

    // MARK: Gate

    @Test func noAccounts_nothingToReveal() {
        #expect(AccountStore.hasRevealableIdentity(in: []) == false)
    }

    @Test func bareEmail_canBeUnmasked() {
        let accounts = [account(discoveredIdentity: "kyle@example.com")]
        #expect(AccountStore.hasRevealableIdentity(in: accounts))
    }

    /// The case this was built for: an alias outranks the discovered email, so the user
    /// sees "API Rates" and has no way to tell which login it is. The toggle now reveals
    /// it, so the row must be offered.
    @Test func aliasedEmail_canBeRevealed() {
        let accounts = [account(displayName: "API Rates", discoveredIdentity: "kyle@example.com")]
        #expect(AccountStore.hasRevealableIdentity(in: accounts))
    }

    /// Claude's discovered identity is a workspace name rather than an email — nothing
    /// to *mask*, but still the answer to "which account is this?" when an alias covers it.
    @Test func aliasedClaudeWorkspace_canBeRevealed() {
        let accounts = [account(displayName: "Work", provider: .claude, discoveredIdentity: "Ringier Workspace")]
        #expect(AccountStore.hasRevealableIdentity(in: accounts))
    }

    /// Unaliased, a workspace name is already fully on screen and `maskedEmail` leaves
    /// it alone, so the toggle has nothing to do.
    @Test func bareClaudeWorkspace_isAlreadyShown() {
        let accounts = [account(provider: .claude, discoveredIdentity: "Ringier Workspace")]
        #expect(AccountStore.hasRevealableIdentity(in: accounts) == false)
    }

    @Test func noDiscoveredIdentity_nothingToReveal() {
        #expect(AccountStore.hasRevealableIdentity(in: [account()]) == false)
        #expect(AccountStore.hasRevealableIdentity(in: [account(displayName: "Mine")]) == false)
    }

    @Test func pendingAccount_readsConnectingAndRevealsNothing() {
        let accounts = [account(id: "pending-1", discoveredIdentity: "kyle@example.com")]
        #expect(AccountStore.hasRevealableIdentity(in: accounts) == false)
    }

    /// Kyle's actual configuration as of 2026-11-02: a named Codex account with a
    /// discovered email, and a named Claude account without one. The Codex account alone
    /// keeps the row worth offering.
    @Test func oneRevealableAmongMany_offersTheToggle() {
        let accounts = [
            account(id: "a1", displayName: "API Rates", discoveredIdentity: "kyle@example.com"),
            account(id: "a2", displayName: "Claude", provider: .claude),
        ]
        #expect(AccountStore.hasRevealableIdentity(in: accounts))
    }

    /// An alias set to the identity itself adds nothing — revealing it would print the
    /// same string twice.
    @Test func aliasEqualToTheIdentity_revealsNothing() {
        let accounts = [account(displayName: "kyle@example.com", discoveredIdentity: "kyle@example.com")]
        #expect(AccountStore.hasRevealableIdentity(in: accounts) == false)
    }

    // MARK: hiddenIdentity

    @Test func hiddenIdentity_isNilWithoutAnAlias() {
        #expect(AccountStore.hiddenIdentity(for: account(discoveredIdentity: "kyle@example.com")) == nil)
    }

    @Test func hiddenIdentity_isTheIdentityAnAliasCovers() {
        let record = account(displayName: "API Rates", discoveredIdentity: "kyle@example.com")
        #expect(AccountStore.hiddenIdentity(for: record) == "kyle@example.com")
    }

    /// A whitespace-only alias doesn't outrank anything in `identityLabel`, so it isn't
    /// covering the identity either.
    @Test func hiddenIdentity_ignoresABlankAlias() {
        let record = account(displayName: "   ", discoveredIdentity: "kyle@example.com")
        #expect(AccountStore.hiddenIdentity(for: record) == nil)
    }

    // MARK: identityLabel

    @Test func identityLabel_putsTheIdentityBesideTheAliasWhenRevealed() {
        let record = account(displayName: "API Rates", discoveredIdentity: "kyle@example.com")
        #expect(
            AccountStore.identityLabel(for: record, providerIndex: 0, maskEmail: false)
                == "API Rates (kyle@example.com)"
        )
    }

    @Test func identityLabel_keepsTheAliasAloneWhenMasked() {
        let record = account(displayName: "API Rates", discoveredIdentity: "kyle@example.com")
        #expect(AccountStore.identityLabel(for: record, providerIndex: 0, maskEmail: true) == "API Rates")
    }

    /// Revealing never masks: the point of the reveal is to name the account exactly, and
    /// a masked address beside an alias would answer nothing.
    @Test func identityLabel_revealsTheAddressInFull() {
        let record = account(displayName: "Work", discoveredIdentity: "kyle@example.com")
        let label = AccountStore.identityLabel(for: record, providerIndex: 0, maskEmail: false)
        #expect(label.contains("kyle@example.com"))
        #expect(!label.contains("•"))
    }

    @Test func identityLabel_leavesAnUnaliasedAccountOnItsOldPath() {
        let record = account(discoveredIdentity: "kyle@example.com")
        #expect(AccountStore.identityLabel(for: record, providerIndex: 0, maskEmail: true) == "k•••@example.com")
        #expect(AccountStore.identityLabel(for: record, providerIndex: 0, maskEmail: false) == "kyle@example.com")
    }

    @Test func identityLabel_fallsBackToTheNumberedNameUnchanged() {
        let record = account()
        #expect(AccountStore.identityLabel(for: record, providerIndex: 1, maskEmail: false) == "Codex 2")
    }
}
