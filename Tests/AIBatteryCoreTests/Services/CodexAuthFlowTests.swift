import Foundation
import Testing
@testable import AIBatteryCore

/// The Codex sign-in paths that used to have no coverage at all: the callback
/// listener's one-shot/CSRF rules, and the registration guards that stand between a
/// sign-in and a persisted Keychain item.
///
/// `OAuthManager.tokenPersistence` is swapped for a sink in every test here, so these
/// exercise the real registration code without writing to the Keychain.
@Suite("Codex auth flow")
@MainActor
struct CodexAuthFlowTests {
    private func makeManager() -> (manager: OAuthManager, persisted: Box<[String]>) {
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.accounts)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.activeAccountId)
        let manager = OAuthManager()
        let persisted = Box<[String]>([])
        manager.tokenPersistence = { _, storageKey in persisted.value.append(storageKey) }
        return (manager, persisted)
    }

    final class Box<Value>: @unchecked Sendable {
        var value: Value
        init(_ value: Value) {
            self.value = value
        }
    }

    // MARK: - Callback disposition (CSRF + noise)

    @Test func callback_withMatchingState_isDelivered() {
        let disposition = CodexCallbackServer.disposition(
            for: .success((code: "c", state: "the-state")), expectedState: "the-state"
        )
        #expect(disposition == .deliver)
    }

    /// Any local process can hit 127.0.0.1:1455/auth/callback. Before the state was
    /// compared here, the first hit won: the mailbox delivered, the listener stopped,
    /// and the genuine redirect landed on a dead port — a denial of sign-in.
    @Test func callback_withForeignState_isIgnoredSoTheRealRedirectStillLands() {
        let disposition = CodexCallbackServer.disposition(
            for: .success((code: "c", state: "attacker")), expectedState: "the-state"
        )
        #expect(disposition == .stateMismatch)
    }

    @Test func callback_onAnotherPath_keepsListening() {
        #expect(CodexCallbackServer.disposition(for: .failure(.notCallbackPath), expectedState: "s") == .notForUs)
    }

    @Test func callback_providerErrorOnOurPath_isDelivered() {
        #expect(CodexCallbackServer.disposition(for: .failure(.providerError("access_denied")), expectedState: "s") == .deliver)
        #expect(CodexCallbackServer.disposition(for: .failure(.missingCode), expectedState: "s") == .deliver)
    }

    // MARK: - registerCodexAPIKey

    @Test func registerAPIKey_malformedKeyIsRejectedWithoutPersisting() {
        let (manager, persisted) = makeManager()
        for bad in ["", "   ", "not-a-key", "sk-short"] {
            let result = manager.registerCodexAPIKey(bad)
            guard case .failure(.unknownError(let message)) = result else {
                Issue.record("\(bad) must be rejected"); continue
            }
            #expect(message == OAuthManager.AuthError.malformedAPIKeyMessage)
        }
        #expect(persisted.value.isEmpty)
        #expect(manager.accountStore.accounts.isEmpty)
    }

    @Test func registerAPIKey_storesUnderTheProviderScopedKeyAndActivates() {
        let (manager, persisted) = makeManager()
        let key = "sk-" + String(repeating: "a", count: 40)
        guard case .success = manager.registerCodexAPIKey(key) else {
            Issue.record("a well-formed key must register"); return
        }
        let accountId = OAuthManager.apiKeyAccountId(for: key)
        #expect(persisted.value == ["codex_\(accountId)"])
        #expect(manager.accountStore.activeAccountId == accountId)
        #expect(manager.accountStore.account(id: accountId)?.isAPIKeyAccount == true)
        // The key itself is never part of the id.
        #expect(!accountId.contains(key))
    }

    // MARK: - Per-provider cap

    @Test func registerCodexAccount_atTheCapFailsWithoutPersistingTokens() {
        let (manager, persisted) = makeManager()
        for i in 1...AccountStore.maxAccountsPerProvider {
            manager.accountStore.add(AccountRecord(id: "codex-\(i)", addedAt: Date(), provider: .codex))
            // Signed in: a signed-out account at the cap would be replaced instead.
            manager.seedTokensForTesting(accountId: "codex-\(i)", accessToken: "at", refreshToken: "rt-\(i)", expiresAt: nil)
        }
        let result = manager.registerCodexAccount(
            accountId: "codex-overflow",
            tokenSet: CodexTokenSet(idToken: nil, accessToken: "at", refreshToken: "rt")
        )
        guard case .failure(.maxAccountsReached) = result else {
            Issue.record("the 4th Codex account must be refused"); return
        }
        // Nothing was written: an orphaned Keychain item is exactly what this guard exists to prevent.
        #expect(persisted.value.isEmpty)
        #expect(manager.accountStore.account(id: "codex-overflow") == nil)
    }

    @Test func registerCodexAccount_reSignInToAKnownAccountIsAllowedAtTheCap() {
        let (manager, persisted) = makeManager()
        for i in 1...AccountStore.maxAccountsPerProvider {
            manager.accountStore.add(AccountRecord(id: "codex-\(i)", addedAt: Date(), provider: .codex))
        }
        let result = manager.registerCodexAccount(
            accountId: "codex-2",
            tokenSet: CodexTokenSet(idToken: nil, accessToken: "at", refreshToken: "rt")
        )
        guard case .success = result else {
            Issue.record("re-signing into an existing account must still work at the cap"); return
        }
        #expect(persisted.value == ["codex_codex-2"])
        #expect(manager.accountStore.activeAccountId == "codex-2")
    }

    /// A signed-out account (its sign-in was rejected, the record kept) does not block a
    /// new sign-in at the cap: the new account replaces it, and the signed-in ones stay.
    @Test func registerCodexAccount_atTheCapReplacesASignedOutAccount() {
        let (manager, persisted) = makeManager()
        for i in 1...AccountStore.maxAccountsPerProvider {
            manager.accountStore.add(AccountRecord(id: "codex-\(i)", addedAt: Date(), provider: .codex))
        }
        manager.seedTokensForTesting(accountId: "codex-1", accessToken: "at", refreshToken: "rt-1", expiresAt: nil)
        manager.seedTokensForTesting(accountId: "codex-3", accessToken: "at", refreshToken: "rt-3", expiresAt: nil)
        #expect(manager.hasRoomForSignIn(provider: .codex))

        let result = manager.registerCodexAccount(
            accountId: "codex-new",
            tokenSet: CodexTokenSet(idToken: nil, accessToken: "at", refreshToken: "rt")
        )
        guard case .success = result else {
            Issue.record("a signed-out account must make room, got \(result)"); return
        }
        #expect(persisted.value == ["codex_codex-new"])
        #expect(manager.accountStore.accounts.map(\.id).sorted() == ["codex-1", "codex-3", "codex-new"])
    }

    /// The Claude cap is separate: 3 Codex accounts must not block a Claude sign-in.
    @Test func codexCapIsPerProvider() {
        let (manager, _) = makeManager()
        for i in 1...AccountStore.maxAccountsPerProvider {
            manager.accountStore.add(AccountRecord(id: "codex-\(i)", addedAt: Date(), provider: .codex))
        }
        #expect(!manager.accountStore.canAddAccount(provider: .codex))
        #expect(manager.accountStore.canAddAccount(provider: .claude))
    }

    // MARK: - completeCodexAuthFlow

    @Test func completeFlow_withoutASessionFails() async {
        let (manager, _) = makeManager()
        guard case .failure(.unknownError(let message)) = await manager.completeCodexAuthFlow() else {
            Issue.record("no in-flight session must be an error"); return
        }
        #expect(message == "No auth flow in progress")
    }
}
