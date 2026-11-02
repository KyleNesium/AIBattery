import Foundation
import Testing
@testable import AIBatteryCore

/// `hasMaskableIdentity` decides whether Settings offers the "Full account email in
/// popover" toggle at all. The toggle only moves a label that *is* a discovered email,
/// so every other shape of account must leave it hidden rather than present a control
/// that visibly does nothing.
@Suite("AccountStore.hasMaskableIdentity")
struct AccountStoreMaskableIdentityTests {
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

    @Test func noAccounts_nothingToMask() {
        #expect(AccountStore.hasMaskableIdentity(in: []) == false)
    }

    @Test func bareEmail_isMaskable() {
        let accounts = [account(discoveredIdentity: "kyle@example.com")]
        #expect(AccountStore.hasMaskableIdentity(in: accounts))
    }

    /// The bug this guard was added for: an alias outranks the discovered email and is
    /// never masked, so the toggle had nothing to act on and read as broken.
    @Test func aliasedEmail_isNotMaskable() {
        let accounts = [account(displayName: "API Rates", discoveredIdentity: "kyle@example.com")]
        #expect(AccountStore.hasMaskableIdentity(in: accounts) == false)
    }

    @Test func blankAliasDoesNotCount_theEmailStillShows() {
        let accounts = [account(displayName: "   ", discoveredIdentity: "kyle@example.com")]
        #expect(AccountStore.hasMaskableIdentity(in: accounts))
    }

    /// Claude's discovered identity is a workspace name, which `maskedEmail` returns
    /// untouched — masked and unmasked agree, so there is nothing to offer.
    @Test func claudeWorkspaceName_isNotMaskable() {
        let accounts = [account(provider: .claude, discoveredIdentity: "Ringier Workspace")]
        #expect(AccountStore.hasMaskableIdentity(in: accounts) == false)
    }

    @Test func noDiscoveredIdentity_isNotMaskable() {
        #expect(AccountStore.hasMaskableIdentity(in: [account()]) == false)
    }

    @Test func pendingAccount_readsConnectingAndIsNotMaskable() {
        let accounts = [account(id: "pending-1", discoveredIdentity: "kyle@example.com")]
        #expect(AccountStore.hasMaskableIdentity(in: accounts) == false)
    }

    /// One unaliased email among aliased accounts is enough to keep the toggle useful.
    @Test func oneMaskableAmongAliased_offersTheToggle() {
        let accounts = [
            account(id: "a1", displayName: "API Rates", discoveredIdentity: "kyle@example.com"),
            account(id: "a2", provider: .claude, discoveredIdentity: "Workspace"),
            account(id: "a3", discoveredIdentity: "other@example.com"),
        ]
        #expect(AccountStore.hasMaskableIdentity(in: accounts))
    }

    /// Kyle's actual configuration as of 2026-11-02: both accounts aliased, so the row
    /// is hidden.
    @Test func everyAccountAliased_hidesTheToggle() {
        let accounts = [
            account(id: "a1", displayName: "API Rates", discoveredIdentity: "kyle@example.com"),
            account(id: "a2", displayName: "Claude", provider: .claude),
        ]
        #expect(AccountStore.hasMaskableIdentity(in: accounts) == false)
    }

    /// An identity that isn't email-shaped can't be masked, so it can't justify the row.
    @Test func nonEmailIdentity_isNotMaskable() {
        #expect(AccountStore.hasMaskableIdentity(in: [account(discoveredIdentity: "no-at-sign")]) == false)
        #expect(AccountStore.hasMaskableIdentity(in: [account(discoveredIdentity: "kyle@localhost")]) == false)
    }
}
