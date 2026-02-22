import Foundation
import Testing
@testable import AIBatteryCore

@Suite("AccountStore")
@MainActor
struct AccountStoreTests {

    /// Clean UserDefaults before each test to avoid cross-contamination.
    private func makeCleanStore() -> AccountStore {
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.accounts)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.activeAccountId)
        return AccountStore()
    }

    @Test func init_emptyByDefault() {
        let store = makeCleanStore()
        #expect(store.accounts.isEmpty)
        #expect(store.activeAccountId == nil)
        #expect(store.activeAccount == nil)
        #expect(store.canAddAccount)
    }

    @Test func add_singleAccount() {
        let store = makeCleanStore()
        let record = AccountRecord(id: "org-1", displayName: "Kyle", organizationName: "Acme", billingType: "pro", addedAt: Date())
        store.add(record)

        #expect(store.accounts.count == 1)
        #expect(store.accounts.first?.id == "org-1")
        #expect(store.activeAccountId == "org-1")
        #expect(store.activeAccount?.id == "org-1")
        #expect(store.canAddAccount) // can still add one more
    }

    @Test func add_twoAccounts() {
        let store = makeCleanStore()
        let r1 = AccountRecord(id: "org-1", displayName: nil, organizationName: nil, billingType: nil, addedAt: Date())
        let r2 = AccountRecord(id: "org-2", displayName: nil, organizationName: nil, billingType: nil, addedAt: Date())
        store.add(r1)
        store.add(r2)

        #expect(store.accounts.count == 2)
        #expect(store.activeAccountId == "org-1") // first added stays active
        #expect(!store.canAddAccount) // at max
    }

    @Test func add_rejectsOverMax() {
        let store = makeCleanStore()
        let r1 = AccountRecord(id: "org-1", displayName: nil, organizationName: nil, billingType: nil, addedAt: Date())
        let r2 = AccountRecord(id: "org-2", displayName: nil, organizationName: nil, billingType: nil, addedAt: Date())
        let r3 = AccountRecord(id: "org-3", displayName: nil, organizationName: nil, billingType: nil, addedAt: Date())
        store.add(r1)
        store.add(r2)
        store.add(r3) // should be rejected

        #expect(store.accounts.count == 2)
    }

    @Test func add_rejectsDuplicate() {
        let store = makeCleanStore()
        let r1 = AccountRecord(id: "org-1", displayName: nil, organizationName: nil, billingType: nil, addedAt: Date())
        store.add(r1)
        store.add(r1) // same ID

        #expect(store.accounts.count == 1)
    }

    @Test func remove_singleAccount() {
        let store = makeCleanStore()
        let r1 = AccountRecord(id: "org-1", displayName: nil, organizationName: nil, billingType: nil, addedAt: Date())
        store.add(r1)
        store.remove(id: "org-1")

        #expect(store.accounts.isEmpty)
        #expect(store.activeAccountId == nil)
        #expect(store.canAddAccount)
    }

    @Test func remove_switchesToOther() {
        let store = makeCleanStore()
        let r1 = AccountRecord(id: "org-1", displayName: nil, organizationName: nil, billingType: nil, addedAt: Date())
        let r2 = AccountRecord(id: "org-2", displayName: nil, organizationName: nil, billingType: nil, addedAt: Date())
        store.add(r1)
        store.add(r2)
        store.setActive(id: "org-1")
        store.remove(id: "org-1")

        #expect(store.accounts.count == 1)
        #expect(store.activeAccountId == "org-2")
    }

    @Test func setActive_changesActiveAccount() {
        let store = makeCleanStore()
        let r1 = AccountRecord(id: "org-1", displayName: nil, organizationName: nil, billingType: nil, addedAt: Date())
        let r2 = AccountRecord(id: "org-2", displayName: nil, organizationName: nil, billingType: nil, addedAt: Date())
        store.add(r1)
        store.add(r2)

        store.setActive(id: "org-2")
        #expect(store.activeAccountId == "org-2")
        #expect(store.activeAccount?.id == "org-2")
    }

    @Test func setActive_ignoresUnknownId() {
        let store = makeCleanStore()
        let r1 = AccountRecord(id: "org-1", displayName: nil, organizationName: nil, billingType: nil, addedAt: Date())
        store.add(r1)

        store.setActive(id: "nonexistent")
        #expect(store.activeAccountId == "org-1") // unchanged
    }

    @Test func update_changesMetadata() {
        let store = makeCleanStore()
        let r1 = AccountRecord(id: "org-1", displayName: "Old", organizationName: "Old Org", billingType: "free", addedAt: Date())
        store.add(r1)

        var updated = r1
        updated.displayName = "New"
        updated.organizationName = "New Org"
        updated.billingType = "pro"
        store.update(oldId: "org-1", with: updated)

        #expect(store.accounts.first?.displayName == "New")
        #expect(store.accounts.first?.organizationName == "New Org")
        #expect(store.accounts.first?.billingType == "pro")
    }

    @Test func update_resolvesIdentity() {
        let store = makeCleanStore()
        let r1 = AccountRecord(id: "pending-abc", displayName: nil, organizationName: nil, billingType: nil, addedAt: Date())
        store.add(r1)
        store.setActive(id: "pending-abc")

        var resolved = r1
        resolved.id = "org-real-123"
        resolved.organizationName = "Acme Corp"
        let oldId = store.update(oldId: "pending-abc", with: resolved)

        #expect(oldId == "pending-abc")
        #expect(store.accounts.first?.id == "org-real-123")
        #expect(store.activeAccountId == "org-real-123")
    }

    @Test func update_mergesDuplicate() {
        let store = makeCleanStore()
        let r1 = AccountRecord(id: "org-real", displayName: "First", organizationName: nil, billingType: nil, addedAt: Date())
        let r2 = AccountRecord(id: "pending-abc", displayName: "Second", organizationName: nil, billingType: nil, addedAt: Date())
        store.add(r1)
        store.add(r2)
        store.setActive(id: "pending-abc")

        // Resolve pending to same org as first account — should merge
        var resolved = r2
        resolved.id = "org-real"
        resolved.displayName = "Merged"
        store.update(oldId: "pending-abc", with: resolved)

        #expect(store.accounts.count == 1)
        #expect(store.accounts.first?.id == "org-real")
        #expect(store.accounts.first?.displayName == "Merged")
        #expect(store.activeAccountId == "org-real")
    }

    @Test func persistence_surviesReinit() {
        let store = makeCleanStore()
        let r1 = AccountRecord(id: "org-1", displayName: "Kyle", organizationName: "Test", billingType: "pro", addedAt: Date(timeIntervalSince1970: 1700000000))
        store.add(r1)

        // Create a new store — should load from UserDefaults
        let store2 = AccountStore()
        #expect(store2.accounts.count == 1)
        #expect(store2.accounts.first?.id == "org-1")
        #expect(store2.accounts.first?.displayName == "Kyle")
        #expect(store2.activeAccountId == "org-1")
    }

    @Test func persistence_fixesDanglingActiveId() {
        let store = makeCleanStore()
        let r1 = AccountRecord(id: "org-1", displayName: nil, organizationName: nil, billingType: nil, addedAt: Date())
        store.add(r1)

        // Manually set a bad active ID
        UserDefaults.standard.set("nonexistent", forKey: UserDefaultsKeys.activeAccountId)

        let store2 = AccountStore()
        #expect(store2.activeAccountId == "org-1") // fixed to first available
    }

    @Test func maxAccounts_isTwo() {
        #expect(AccountStore.maxAccounts == 2)
    }

    // MARK: - Edge cases

    @Test func update_unknownOldId_returnsNil() {
        let store = makeCleanStore()
        let r1 = AccountRecord(id: "org-1", displayName: nil, organizationName: nil, billingType: nil, addedAt: Date())
        store.add(r1)

        var ghost = r1
        ghost.id = "org-999"
        let result = store.update(oldId: "nonexistent", with: ghost)

        #expect(result == nil)
        #expect(store.accounts.count == 1)
        #expect(store.accounts.first?.id == "org-1")
    }

    @Test func update_sameIdReturnsNil() {
        let store = makeCleanStore()
        let r1 = AccountRecord(id: "org-1", displayName: "Old", organizationName: nil, billingType: nil, addedAt: Date())
        store.add(r1)

        var updated = r1
        updated.displayName = "New"
        let result = store.update(oldId: "org-1", with: updated)

        // ID didn't change, so oldId return should be nil
        #expect(result == nil)
        #expect(store.accounts.first?.displayName == "New")
    }

    @Test func update_mergeWhenExistingAtLowerIndex() {
        let store = makeCleanStore()
        // existing real account at index 0, pending at index 1
        let r1 = AccountRecord(id: "org-real", displayName: "First", organizationName: "Org A", billingType: nil, addedAt: Date())
        let r2 = AccountRecord(id: "pending-xyz", displayName: "Second", organizationName: nil, billingType: nil, addedAt: Date())
        store.add(r1)
        store.add(r2)

        // Active is the first account
        store.setActive(id: "org-real")

        // Resolve pending → same org as r1 (existingIndex=0 < index=1)
        var resolved = r2
        resolved.id = "org-real"
        resolved.displayName = "Merged"
        resolved.organizationName = "Org B"
        store.update(oldId: "pending-xyz", with: resolved)

        #expect(store.accounts.count == 1)
        #expect(store.accounts.first?.id == "org-real")
        #expect(store.accounts.first?.displayName == "Merged")
        #expect(store.accounts.first?.organizationName == "Org B")
        // Active should remain org-real (unchanged since it wasn't the pending one)
        #expect(store.activeAccountId == "org-real")
    }

    @Test func remove_nonActiveAccount_doesNotChangeActive() {
        let store = makeCleanStore()
        let r1 = AccountRecord(id: "org-1", displayName: nil, organizationName: nil, billingType: nil, addedAt: Date())
        let r2 = AccountRecord(id: "org-2", displayName: nil, organizationName: nil, billingType: nil, addedAt: Date())
        store.add(r1)
        store.add(r2)
        store.setActive(id: "org-1")

        store.remove(id: "org-2")

        #expect(store.accounts.count == 1)
        #expect(store.activeAccountId == "org-1") // unchanged
        #expect(store.canAddAccount)
    }

    @Test func remove_nonexistentId_isNoOp() {
        let store = makeCleanStore()
        let r1 = AccountRecord(id: "org-1", displayName: nil, organizationName: nil, billingType: nil, addedAt: Date())
        store.add(r1)

        store.remove(id: "ghost")

        #expect(store.accounts.count == 1)
        #expect(store.activeAccountId == "org-1")
    }

    @Test func persistence_emptyAccountsArray() {
        _ = makeCleanStore()
        // Don't add anything — just re-init
        let store2 = AccountStore()
        #expect(store2.accounts.isEmpty)
        #expect(store2.activeAccountId == nil)
    }

    @Test func persistence_twoAccountsSurviveReinit() {
        let store = makeCleanStore()
        let r1 = AccountRecord(id: "org-1", displayName: "A", organizationName: nil, billingType: nil, addedAt: Date(timeIntervalSince1970: 1700000000))
        let r2 = AccountRecord(id: "org-2", displayName: "B", organizationName: nil, billingType: nil, addedAt: Date(timeIntervalSince1970: 1700000000))
        store.add(r1)
        store.add(r2)
        store.setActive(id: "org-2")

        let store2 = AccountStore()
        #expect(store2.accounts.count == 2)
        #expect(store2.activeAccountId == "org-2")
        #expect(store2.accounts[0].id == "org-1")
        #expect(store2.accounts[1].id == "org-2")
    }
}
