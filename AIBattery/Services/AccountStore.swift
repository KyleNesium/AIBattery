import Foundation
import os

/// Manages the list of authenticated Claude accounts and which one is active.
///
/// Persists to UserDefaults as a JSON array. Owned by `OAuthManager` and
/// published so SwiftUI views react to account changes.
@MainActor
public final class AccountStore: ObservableObject {
    /// Maximum number of accounts supported.
    nonisolated static let maxAccounts = 2

    @Published public private(set) var accounts: [AccountRecord] = []
    @Published public var activeAccountId: String?

    public var activeAccount: AccountRecord? {
        accounts.first { $0.id == activeAccountId }
    }

    public var canAddAccount: Bool {
        accounts.count < Self.maxAccounts
    }

    public init() {
        load()
    }

    // MARK: - Mutations

    public func add(_ record: AccountRecord) {
        guard accounts.count < Self.maxAccounts else {
            AppLogger.oauth.warning("Cannot add account — max \(Self.maxAccounts) reached")
            return
        }
        guard !accounts.contains(where: { $0.id == record.id }) else {
            AppLogger.oauth.warning("Account \(record.id, privacy: .public) already exists")
            return
        }
        accounts.append(record)
        if activeAccountId == nil {
            activeAccountId = record.id
        }
        save()
    }

    public func remove(id: String) {
        accounts.removeAll { $0.id == id }
        if activeAccountId == id {
            activeAccountId = accounts.first?.id
        }
        save()
    }

    public func setActive(id: String) {
        guard accounts.contains(where: { $0.id == id }) else { return }
        activeAccountId = id
        save()
    }

    /// Replace an account record (e.g. resolve pending ID to real org ID).
    /// Returns the old ID if it changed, nil otherwise.
    @discardableResult
    public func update(oldId: String, with newRecord: AccountRecord) -> String? {
        guard let index = accounts.firstIndex(where: { $0.id == oldId }) else { return nil }

        // Check for duplicate: another account already has this real org ID
        if newRecord.id != oldId,
           let existingIndex = accounts.firstIndex(where: { $0.id == newRecord.id }) {
            // Merge: preserve earliest addedAt and existing metadata the new record doesn't set
            let existing = accounts[existingIndex]
            var merged = newRecord
            merged.addedAt = min(existing.addedAt, newRecord.addedAt)
            if merged.displayName == nil { merged.displayName = existing.displayName }
            if merged.billingType == nil { merged.billingType = existing.billingType }

            AppLogger.oauth.info("Merging duplicate account \(oldId, privacy: .public) → \(newRecord.id, privacy: .public)")

            // Remove in descending index order to avoid shifting issues
            if index > existingIndex {
                accounts.remove(at: index)
                accounts[existingIndex] = merged
            } else {
                accounts[existingIndex] = merged
                accounts.remove(at: index)
            }
            if activeAccountId == oldId {
                activeAccountId = merged.id
            }
            save()
            return oldId
        }

        accounts[index] = newRecord
        if activeAccountId == oldId {
            activeAccountId = newRecord.id
        }
        save()
        return oldId != newRecord.id ? oldId : nil
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        UserDefaults.standard.set(data, forKey: UserDefaultsKeys.accounts)
        UserDefaults.standard.set(activeAccountId, forKey: UserDefaultsKeys.activeAccountId)
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: UserDefaultsKeys.accounts),
           let decoded = try? JSONDecoder().decode([AccountRecord].self, from: data) {
            accounts = decoded
        }
        activeAccountId = UserDefaults.standard.string(forKey: UserDefaultsKeys.activeAccountId)
        // Fix active ID pointing at a removed account
        if let active = activeAccountId, !accounts.contains(where: { $0.id == active }) {
            activeAccountId = accounts.first?.id
        }
    }
}
