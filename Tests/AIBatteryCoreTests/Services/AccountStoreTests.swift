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
        let record = AccountRecord(id: "org-1", displayName: "Kyle", billingType: "pro", addedAt: Date())
        store.add(record)

        #expect(store.accounts.count == 1)
        #expect(store.accounts.first?.id == "org-1")
        #expect(store.activeAccountId == "org-1")
        #expect(store.activeAccount?.id == "org-1")
        #expect(store.canAddAccount)
    }

    @Test func add_twoAccounts() {
        let store = makeCleanStore()
        let r1 = AccountRecord(id: "org-1", displayName: nil, billingType: nil, addedAt: Date())
        let r2 = AccountRecord(id: "org-2", displayName: nil, billingType: nil, addedAt: Date())
        store.add(r1)
        store.add(r2)

        #expect(store.accounts.count == 2)
        #expect(store.activeAccountId == "org-1")
        #expect(!store.canAddAccount)
    }

    @Test func add_rejectsOverMax() {
        let store = makeCleanStore()
        let r1 = AccountRecord(id: "org-1", displayName: nil, billingType: nil, addedAt: Date())
        let r2 = AccountRecord(id: "org-2", displayName: nil, billingType: nil, addedAt: Date())
        let r3 = AccountRecord(id: "org-3", displayName: nil, billingType: nil, addedAt: Date())
        store.add(r1)
        store.add(r2)
        store.add(r3)

        #expect(store.accounts.count == 2)
    }

    @Test func add_rejectsDuplicate() {
        let store = makeCleanStore()
        let r1 = AccountRecord(id: "org-1", displayName: nil, billingType: nil, addedAt: Date())
        store.add(r1)
        store.add(r1)

        #expect(store.accounts.count == 1)
    }

    @Test func remove_singleAccount() {
        let store = makeCleanStore()
        let r1 = AccountRecord(id: "org-1", displayName: nil, billingType: nil, addedAt: Date())
        store.add(r1)
        store.remove(id: "org-1")

        #expect(store.accounts.isEmpty)
        #expect(store.activeAccountId == nil)
        #expect(store.canAddAccount)
    }

    @Test func remove_switchesToOther() {
        let store = makeCleanStore()
        let r1 = AccountRecord(id: "org-1", displayName: nil, billingType: nil, addedAt: Date())
        let r2 = AccountRecord(id: "org-2", displayName: nil, billingType: nil, addedAt: Date())
        store.add(r1)
        store.add(r2)
        store.setActive(id: "org-1")
        store.remove(id: "org-1")

        #expect(store.accounts.count == 1)
        #expect(store.activeAccountId == "org-2")
    }

    @Test func setActive_changesActiveAccount() {
        let store = makeCleanStore()
        let r1 = AccountRecord(id: "org-1", displayName: nil, billingType: nil, addedAt: Date())
        let r2 = AccountRecord(id: "org-2", displayName: nil, billingType: nil, addedAt: Date())
        store.add(r1)
        store.add(r2)

        store.setActive(id: "org-2")
        #expect(store.activeAccountId == "org-2")
        #expect(store.activeAccount?.id == "org-2")
    }

    @Test func setActive_ignoresUnknownId() {
        let store = makeCleanStore()
        let r1 = AccountRecord(id: "org-1", displayName: nil, billingType: nil, addedAt: Date())
        store.add(r1)

        store.setActive(id: "nonexistent")
        #expect(store.activeAccountId == "org-1")
    }

    @Test func update_changesMetadata() {
        let store = makeCleanStore()
        let r1 = AccountRecord(id: "org-1", displayName: "Old", billingType: "free", addedAt: Date())
        store.add(r1)

        var updated = r1
        updated.displayName = "New"
        updated.billingType = "pro"
        store.update(oldId: "org-1", with: updated)

        #expect(store.accounts.first?.displayName == "New")
        #expect(store.accounts.first?.billingType == "pro")
    }

    @Test func update_resolvesIdentity() {
        let store = makeCleanStore()
        let r1 = AccountRecord(id: "pending-abc", displayName: nil, billingType: nil, addedAt: Date())
        store.add(r1)
        store.setActive(id: "pending-abc")

        var resolved = r1
        resolved.id = "org-real-123"
        let oldId = store.update(oldId: "pending-abc", with: resolved)

        #expect(oldId == "pending-abc")
        #expect(store.accounts.first?.id == "org-real-123")
        #expect(store.activeAccountId == "org-real-123")
    }

    @Test func update_mergesDuplicate() {
        let store = makeCleanStore()
        let r1 = AccountRecord(id: "org-real", displayName: "First", billingType: nil, addedAt: Date())
        let r2 = AccountRecord(id: "pending-abc", displayName: "Second", billingType: nil, addedAt: Date())
        store.add(r1)
        store.add(r2)
        store.setActive(id: "pending-abc")

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
        let r1 = AccountRecord(id: "org-1", displayName: "Kyle", billingType: "pro", addedAt: Date(timeIntervalSince1970: 1700000000))
        store.add(r1)

        let store2 = AccountStore()
        #expect(store2.accounts.count == 1)
        #expect(store2.accounts.first?.id == "org-1")
        #expect(store2.accounts.first?.displayName == "Kyle")
        #expect(store2.activeAccountId == "org-1")
    }

    @Test func persistence_fixesDanglingActiveId() {
        let store = makeCleanStore()
        let r1 = AccountRecord(id: "org-1", displayName: nil, billingType: nil, addedAt: Date())
        store.add(r1)

        UserDefaults.standard.set("nonexistent", forKey: UserDefaultsKeys.activeAccountId)

        let store2 = AccountStore()
        #expect(store2.activeAccountId == "org-1")
    }

    @Test func maxAccounts_isTwo() {
        #expect(AccountStore.maxAccounts == 2)
    }

    // MARK: - Edge cases

    @Test func update_unknownOldId_returnsNil() {
        let store = makeCleanStore()
        let r1 = AccountRecord(id: "org-1", displayName: nil, billingType: nil, addedAt: Date())
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
        let r1 = AccountRecord(id: "org-1", displayName: "Old", billingType: nil, addedAt: Date())
        store.add(r1)

        var updated = r1
        updated.displayName = "New"
        let result = store.update(oldId: "org-1", with: updated)

        #expect(result == nil)
        #expect(store.accounts.first?.displayName == "New")
    }

    @Test func update_mergeWhenExistingAtLowerIndex() {
        let store = makeCleanStore()
        let r1 = AccountRecord(id: "org-real", displayName: "First", billingType: nil, addedAt: Date())
        let r2 = AccountRecord(id: "pending-xyz", displayName: "Second", billingType: nil, addedAt: Date())
        store.add(r1)
        store.add(r2)

        store.setActive(id: "org-real")

        var resolved = r2
        resolved.id = "org-real"
        resolved.displayName = "Merged"
        resolved.billingType = "pro"
        store.update(oldId: "pending-xyz", with: resolved)

        #expect(store.accounts.count == 1)
        #expect(store.accounts.first?.id == "org-real")
        #expect(store.accounts.first?.displayName == "Merged")
        #expect(store.accounts.first?.billingType == "pro")
        #expect(store.activeAccountId == "org-real")
    }

    @Test func remove_nonActiveAccount_doesNotChangeActive() {
        let store = makeCleanStore()
        let r1 = AccountRecord(id: "org-1", displayName: nil, billingType: nil, addedAt: Date())
        let r2 = AccountRecord(id: "org-2", displayName: nil, billingType: nil, addedAt: Date())
        store.add(r1)
        store.add(r2)
        store.setActive(id: "org-1")

        store.remove(id: "org-2")

        #expect(store.accounts.count == 1)
        #expect(store.activeAccountId == "org-1")
        #expect(store.canAddAccount)
    }

    @Test func remove_nonexistentId_isNoOp() {
        let store = makeCleanStore()
        let r1 = AccountRecord(id: "org-1", displayName: nil, billingType: nil, addedAt: Date())
        store.add(r1)

        store.remove(id: "ghost")

        #expect(store.accounts.count == 1)
        #expect(store.activeAccountId == "org-1")
    }

    @Test func update_mergePreservesEarliestAddedAt() {
        let store = makeCleanStore()
        let earlier = Date(timeIntervalSince1970: 1000)
        let later = Date(timeIntervalSince1970: 2000)
        let r1 = AccountRecord(id: "org-real", displayName: nil, billingType: nil, addedAt: earlier)
        let r2 = AccountRecord(id: "pending-abc", displayName: nil, billingType: nil, addedAt: later)
        store.add(r1)
        store.add(r2)

        var resolved = r2
        resolved.id = "org-real"
        store.update(oldId: "pending-abc", with: resolved)

        #expect(store.accounts.count == 1)
        #expect(store.accounts.first?.addedAt == earlier)
    }

    @Test func update_mergePreservesExistingDisplayName() {
        let store = makeCleanStore()
        let r1 = AccountRecord(id: "org-real", displayName: "Kyle", billingType: nil, addedAt: Date())
        let r2 = AccountRecord(id: "pending-abc", displayName: nil, billingType: nil, addedAt: Date())
        store.add(r1)
        store.add(r2)

        var resolved = r2
        resolved.id = "org-real"
        store.update(oldId: "pending-abc", with: resolved)

        #expect(store.accounts.count == 1)
        #expect(store.accounts.first?.displayName == "Kyle")
    }

    @Test func update_mergePrefersNewDisplayName() {
        let store = makeCleanStore()
        let r1 = AccountRecord(id: "org-real", displayName: "Old", billingType: nil, addedAt: Date())
        let r2 = AccountRecord(id: "pending-abc", displayName: nil, billingType: nil, addedAt: Date())
        store.add(r1)
        store.add(r2)

        var resolved = r2
        resolved.id = "org-real"
        resolved.displayName = "New"
        store.update(oldId: "pending-abc", with: resolved)

        #expect(store.accounts.count == 1)
        #expect(store.accounts.first?.displayName == "New")
    }

    @Test func update_mergePrefersNewBillingType() {
        let store = makeCleanStore()
        let r1 = AccountRecord(id: "org-real", displayName: nil, billingType: "free", addedAt: Date())
        let r2 = AccountRecord(id: "pending-abc", displayName: nil, billingType: nil, addedAt: Date())
        store.add(r1)
        store.add(r2)

        var resolved = r2
        resolved.id = "org-real"
        resolved.billingType = "pro"
        store.update(oldId: "pending-abc", with: resolved)

        #expect(store.accounts.count == 1)
        #expect(store.accounts.first?.billingType == "pro")
    }

    @Test func update_mergeFallsBackToExistingBillingType() {
        let store = makeCleanStore()
        let r1 = AccountRecord(id: "org-real", displayName: nil, billingType: "teams", addedAt: Date())
        let r2 = AccountRecord(id: "pending-abc", displayName: nil, billingType: nil, addedAt: Date())
        store.add(r1)
        store.add(r2)

        var resolved = r2
        resolved.id = "org-real"
        store.update(oldId: "pending-abc", with: resolved)

        #expect(store.accounts.count == 1)
        #expect(store.accounts.first?.billingType == "teams")
    }

    @Test func persistence_emptyAccountsArray() {
        _ = makeCleanStore()
        let store2 = AccountStore()
        #expect(store2.accounts.isEmpty)
        #expect(store2.activeAccountId == nil)
    }

    @Test func persistence_twoAccountsSurviveReinit() {
        let store = makeCleanStore()
        let r1 = AccountRecord(id: "org-1", displayName: "A", billingType: nil, addedAt: Date(timeIntervalSince1970: 1700000000))
        let r2 = AccountRecord(id: "org-2", displayName: "B", billingType: nil, addedAt: Date(timeIntervalSince1970: 1700000000))
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
