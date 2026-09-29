import Foundation
import Testing
@testable import AIBatteryCore

@Suite("AccountStore provider caps")
@MainActor
struct AccountStoreProviderTests {
    private func makeCleanStore() -> AccountStore {
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.accounts)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.activeAccountId)
        return AccountStore()
    }

    private func record(_ id: String, _ provider: AIProvider) -> AccountRecord {
        AccountRecord(id: id, addedAt: Date(), provider: provider)
    }

    @Test func capIsPerProvider() {
        let store = makeCleanStore()
        for i in 1...3 {
            store.add(record("c\(i)", .claude))
        }
        #expect(!store.canAddAccount(provider: .claude))
        #expect(store.canAddAccount(provider: .codex)) // full Claude side must not block Codex
        for i in 1...3 {
            store.add(record("x\(i)", .codex))
        }
        #expect(store.accounts.count == 6)
        #expect(!store.canAddAccount(provider: .codex))
        store.add(record("x4", .codex)) // over cap — must be rejected
        #expect(store.accounts.count == 6)
    }

    @Test func displayOrdered_groupsClaudeFirst_stableWithinProvider() {
        let mixed = [
            record("x1", .codex), record("c1", .claude),
            record("x2", .codex), record("c2", .claude),
        ]
        let ordered = AccountStore.displayOrdered(mixed).map(\.id)
        #expect(ordered == ["c1", "c2", "x1", "x2"])
    }

    @Test func multiAccountDisplayIDs_usesDisplayOrder() {
        let mixed = [record("x1", .codex), record("c1", .claude)]
        let ids = AccountStore.multiAccountDisplayIDs(accounts: mixed, isAuthenticated: { _ in true })
        #expect(ids == ["c1", "x1"])
    }

    /// An API-key account has no windowed `RateLimitUsage`, so the multi-account menu
    /// bar would show a permanent "—" for it. It is excluded from the display set.
    @Test func multiAccountDisplayIDs_excludesAPIKeyAccounts() {
        let apiKey = AccountRecord(id: "openai-api-abc", billingType: "api", addedAt: Date(), provider: .codex, codexAccessMode: .apiKey)
        let ids = AccountStore.multiAccountDisplayIDs(accounts: [record("c1", .claude), apiKey, record("x1", .codex)], isAuthenticated: { _ in true })
        #expect(ids == ["c1", "x1"])
    }

    @Test func displayLabel_sharedByPickerAndSettings() {
        var codex = record("x1", .codex)
        codex.billingType = "business"
        let claude = record("c1", .claude)
        #expect(AccountStore.displayLabel(for: claude, index: 0, showsProviderGlyph: true, includePlan: true) == "✦ User 1")
        #expect(AccountStore.displayLabel(for: codex, index: 1, showsProviderGlyph: true, includePlan: true) == "⬡ User 2 · Business")
        #expect(AccountStore.displayLabel(for: codex, index: 1, showsProviderGlyph: true, includePlan: false) == "⬡ User 2")
        #expect(AccountStore.displayLabel(for: codex, index: 0, showsProviderGlyph: false, includePlan: true) == "User 1 · Business")
        var named = codex
        named.displayName = "Work"
        #expect(AccountStore.displayLabel(for: named, index: 1, showsProviderGlyph: false, includePlan: true) == "Work · Business")
        #expect(AccountStore.planLabel("chatgpt_team") == "ChatGPT Team")
        #expect(AccountStore.planLabel("enterprise") == "Enterprise")
        #expect(AccountStore.planLabel("api") == "API")
    }

    @Test func lookupHelpers_defaultUnknownIdsToClaude() {
        let store = makeCleanStore()
        store.add(record("c1", .claude))
        store.add(record("x1", .codex))
        #expect(store.account(id: "x1")?.provider == .codex)
        #expect(store.account(id: "nope") == nil)
        #expect(store.provider(of: "x1") == .codex)
        #expect(store.provider(of: "nope") == .claude)
        #expect(store.provider(of: nil) == .claude)
    }
}
