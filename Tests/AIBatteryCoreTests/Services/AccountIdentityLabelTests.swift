import Foundation
import Testing
@testable import AIBatteryCore

/// The header account chip and the Settings rows share one identity vocabulary:
/// user alias → discovered identity (email / workspace, masked by default) →
/// "<Provider> N" numbered within the provider. Pending records read "Connecting…".
@Suite("Account identity labels")
struct AccountIdentityLabelTests {
    private func record(_ id: String, _ provider: AIProvider, name: String? = nil, discovered: String? = nil, plan: String? = nil) -> AccountRecord {
        AccountRecord(id: id, displayName: name, billingType: plan, addedAt: Date(), provider: provider, discoveredIdentity: discovered)
    }

    // MARK: Numbering

    @Test func providerIndex_countsWithinProviderNotGlobally() {
        let accounts = [record("c1", .claude), record("c2", .claude), record("x1", .codex), record("x2", .codex)]
        #expect(AccountStore.providerIndex(of: accounts[0], in: accounts) == 0)
        #expect(AccountStore.providerIndex(of: accounts[1], in: accounts) == 1)
        // The first Codex account is "Codex 1", not "User 3".
        #expect(AccountStore.providerIndex(of: accounts[2], in: accounts) == 0)
        #expect(AccountStore.providerIndex(of: accounts[3], in: accounts) == 1)
    }

    @Test func providerIndex_followsDisplayOrderNotInsertionOrder() {
        let accounts = [record("x2", .codex), record("c1", .claude), record("x1", .codex)]
        // displayOrdered keeps insertion order within a provider: x2 is first among Codex.
        #expect(AccountStore.providerIndex(of: accounts[0], in: accounts) == 0)
        #expect(AccountStore.providerIndex(of: accounts[2], in: accounts) == 1)
    }

    @Test func providerIndex_unknownAccountIsZero() {
        let accounts = [record("c1", .claude)]
        #expect(AccountStore.providerIndex(of: record("ghost", .codex), in: accounts) == 0)
    }

    // MARK: Precedence

    @Test func identityLabel_fallsBackToProviderNumbering() {
        #expect(AccountStore.identityLabel(for: record("c1", .claude), providerIndex: 0, maskEmail: true) == "Claude 1")
        #expect(AccountStore.identityLabel(for: record("x1", .codex), providerIndex: 2, maskEmail: true) == "Codex 3")
    }

    @Test func identityLabel_prefersUserAliasOverDiscoveredIdentity() {
        let account = record("x1", .codex, name: "Work", discovered: "kyle@example.com")
        #expect(AccountStore.identityLabel(for: account, providerIndex: 0, maskEmail: true) == "Work")
        #expect(AccountStore.identityLabel(for: account, providerIndex: 0, maskEmail: false) == "Work")
    }

    @Test func identityLabel_blankAliasFallsThroughToDiscovered() {
        let account = record("x1", .codex, name: "   ", discovered: "kyle@example.com")
        #expect(AccountStore.identityLabel(for: account, providerIndex: 0, maskEmail: false) == "kyle@example.com")
    }

    @Test func identityLabel_masksDiscoveredEmailByDefault() {
        let account = record("x1", .codex, discovered: "kyle@example.com")
        #expect(AccountStore.identityLabel(for: account, providerIndex: 0, maskEmail: true) == "k•••@example.com")
        #expect(AccountStore.identityLabel(for: account, providerIndex: 0, maskEmail: false) == "kyle@example.com")
    }

    @Test func identityLabel_workspaceNameIsNotMasked() {
        // Claude's discovered identity is a workspace name, never an email: masking is a no-op.
        let account = record("org-1", .claude, discovered: "Ringier Engineering")
        #expect(AccountStore.identityLabel(for: account, providerIndex: 0, maskEmail: true) == "Ringier Engineering")
    }

    @Test func identityLabel_pendingRecordsReadConnecting() {
        let pending = record("pending-ABC", .claude, discovered: "Should not show")
        #expect(AccountStore.identityLabel(for: pending, providerIndex: 0, maskEmail: true) == "Connecting…")
        // A user alias still wins over the pending placeholder — they typed it on purpose.
        let aliased = record("pending-ABC", .claude, name: "Personal")
        #expect(AccountStore.identityLabel(for: aliased, providerIndex: 0, maskEmail: true) == "Personal")
    }

    // MARK: Email masking

    @Test func maskedEmail_keepsFirstCharacterAndDomain() {
        #expect(AccountStore.maskedEmail("kyle@example.com") == "k•••@example.com")
        #expect(AccountStore.maskedEmail("a@b.co") == "a•••@b.co")
    }

    @Test func maskedEmail_leavesNonEmailsUntouched() {
        #expect(AccountStore.maskedEmail("Ringier Engineering") == "Ringier Engineering")
        #expect(AccountStore.maskedEmail("@") == "@")
        #expect(AccountStore.maskedEmail("") == "")
    }

    // MARK: Full label (menu rows + Settings rows)

    @Test func displayLabel_composesGlyphIdentityAndPlan() {
        let codex = record("x1", .codex, discovered: "kyle@example.com", plan: "business")
        #expect(AccountStore.displayLabel(for: codex, providerIndex: 0, showsProviderGlyph: true, includePlan: true, maskEmail: false) == "⬡ kyle@example.com · Business")
        #expect(AccountStore.displayLabel(for: codex, providerIndex: 0, showsProviderGlyph: false, includePlan: true, maskEmail: true) == "k•••@example.com · Business")
        #expect(AccountStore.displayLabel(for: codex, providerIndex: 0, showsProviderGlyph: false, includePlan: false, maskEmail: true) == "k•••@example.com")
        let claude = record("c1", .claude)
        #expect(AccountStore.displayLabel(for: claude, providerIndex: 1, showsProviderGlyph: true, includePlan: true, maskEmail: true) == "✦ Claude 2")
    }

    @Test func displayLabel_omitsPlanForAPIKeyAndUnknownPlans() {
        let apiKey = AccountRecord(id: "openai-api-1", billingType: "api", addedAt: Date(), provider: .codex, codexAccessMode: .apiKey)
        // The API-key suffix is still meaningful in the full label ("· API") —
        // what must never appear is a dangling separator for an unknown plan.
        #expect(AccountStore.displayLabel(for: apiKey, providerIndex: 0, showsProviderGlyph: false, includePlan: true, maskEmail: true) == "Codex 1 · API")
        let unknown = record("x2", .codex, plan: "   ")
        #expect(AccountStore.displayLabel(for: unknown, providerIndex: 1, showsProviderGlyph: false, includePlan: true, maskEmail: true) == "Codex 2")
    }

    // MARK: Chip accessibility

    @Test func chipAccessibilityDescription_isOneCoherentSentence() {
        let codex = record("x1", .codex, discovered: "kyle@example.com", plan: "business")
        #expect(
            AccountChipView.accessibilityDescription(for: codex, providerIndex: 0, isActive: true, maskEmail: true)
                == "Codex account, k•••@example.com, Business, selected"
        )
        let claude = record("c1", .claude)
        #expect(
            AccountChipView.accessibilityDescription(for: claude, providerIndex: 0, isActive: false, maskEmail: true)
                == "Claude account, Claude 1"
        )
    }
}
