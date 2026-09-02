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
        for i in 1...3 { store.add(record("c\(i)", .claude)) }
        #expect(!store.canAddAccount(provider: .claude))
        #expect(store.canAddAccount(provider: .codex)) // full Claude side must not block Codex
        #expect(store.canAddAccount) // any-provider variant
        for i in 1...3 { store.add(record("x\(i)", .codex)) }
        #expect(store.accounts.count == 6)
        #expect(!store.canAddAccount)
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
}
