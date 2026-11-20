import Foundation
import Testing
@testable import AIBatteryCore

/// The launch read of the saved sign-ins runs off the main thread, so the menu bar icon is
/// up before any Keychain prompt (3.6.0). Until then `OAuthManager.init` read the item
/// synchronously, and after every update the icon stayed missing until the prompt was
/// answered. In the test process `RefreshTokenVault.shared` is an in-memory store.
@Suite("OAuthManager — launch load", .serialized)
@MainActor
struct OAuthManagerLaunchLoadTests {
    /// Registers accounts in `UserDefaults.standard` the way a previous launch left them,
    /// and returns a closure that removes them and their stored tokens again.
    private static func previousLaunch(_ records: [AccountRecord], tokens: [String: String], active: String) -> () -> Void {
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.accounts)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.activeAccountId)
        let store = AccountStore()
        for record in records {
            store.add(record)
        }
        store.setActive(id: active)
        for (id, token) in tokens {
            RefreshTokenVault.shared.set(token, for: id)
        }
        return {
            for record in records {
                OAuthTokenStorage.delete(for: record.id)
            }
            UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.accounts)
            UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.activeAccountId)
        }
    }

    /// `init` returns before the read is applied: the account counts as signed in (its
    /// last reading stays up) and the load has not finished. Nothing here awaits, so the
    /// load's main-actor tail cannot have run yet.
    @Test func initReturnsBeforeTheSavedSignInsAreRead() async {
        let id = "launch-\(UUID().uuidString)"
        let cleanup = Self.previousLaunch([AccountRecord(id: id, addedAt: Date())], tokens: [id: "rt-saved"], active: id)
        defer { cleanup() }

        let manager = OAuthManager()
        #expect(!manager.savedSignInsLoaded)
        #expect(manager.isAuthenticated(accountId: id))
        #expect(manager.isAuthenticated)

        await manager.pendingKeychainRetry(accountId: id)?.value
        #expect(manager.savedSignInsLoaded)
        #expect(manager.isAuthenticated(accountId: id))
    }

    /// An account whose token is gone becomes a sign-in card once the read ends, and the
    /// popover moves to the account that is still signed in.
    @Test func anAccountWithoutATokenEndsSignedOutAndKept() async {
        let gone = "gone-\(UUID().uuidString)"
        let kept = "kept-\(UUID().uuidString)"
        let cleanup = Self.previousLaunch(
            [AccountRecord(id: gone, addedAt: Date()), AccountRecord(id: kept, addedAt: Date())],
            tokens: [kept: "rt-kept"],
            active: gone
        )
        defer { cleanup() }

        let manager = OAuthManager()
        #expect(manager.isAuthenticated(accountId: gone), "until the read ends, every account counts as signed in")
        await manager.pendingKeychainRetry(accountId: gone)?.value

        #expect(!manager.isAuthenticated(accountId: gone))
        #expect(manager.accountStore.account(id: gone) != nil, "a missing token must not remove the account")
        #expect(manager.isAuthenticated(accountId: kept))
        #expect(manager.accountStore.activeAccountId == kept)
        #expect(manager.isAuthenticated)
    }

    /// A refresh during the load shares its read instead of starting a second one, and
    /// returns nil this cycle (the last reading stays up).
    @Test func aRefreshDuringTheLoadWaitsForIt() async {
        let id = "during-\(UUID().uuidString)"
        let cleanup = Self.previousLaunch([AccountRecord(id: id, addedAt: Date())], tokens: [id: "rt-saved"], active: id)
        defer { cleanup() }

        let manager = OAuthManager()
        let load = manager.pendingKeychainRetry(accountId: id)
        #expect(load != nil)
        #expect(await manager.getAccessToken(for: id) == nil)
        await load?.value
        #expect(manager.isAuthenticated(accountId: id))
    }

    /// With no accounts there is nothing to read, and nothing to wait for.
    @Test func noAccountsLoadsAtOnce() {
        let cleanup = Self.previousLaunch([], tokens: [:], active: "")
        defer { cleanup() }

        let manager = OAuthManager()
        #expect(manager.savedSignInsLoaded)
        #expect(!manager.isAuthenticated)
    }
}
