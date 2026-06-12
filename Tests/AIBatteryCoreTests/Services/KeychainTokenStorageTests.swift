import Testing
import Foundation
@testable import AIBatteryCore

/// Real-Keychain roundtrip tests for the layer the accessibility migration (T5)
/// modifies. Uses UUID-suffixed account names so runs never collide with the
/// app's real entries (service "AIBattery", account "refreshToken_{orgId}") or
/// with each other; every test deletes what it created.
///
/// CI caveat: the macos-15 runner's keychain may deny ad-hoc-signed test
/// runners — if these fail there with errSecInteractionNotAllowed-style
/// statuses, gate them on an env check and keep them local.
@Suite("KeychainHelper + OAuthTokenStorage")
struct KeychainTokenStorageTests {
    private static func makeAccount() -> String {
        "test-keychain-\(UUID().uuidString)"
    }

    // MARK: - KeychainHelper

    @Test func setGetDelete_roundtrip() {
        let account = Self.makeAccount()
        defer { KeychainHelper.delete(account: account) }

        let didSet = KeychainHelper.set(account: account, value: "secret-1")
        #expect(didSet)
        #expect(KeychainHelper.get(account: account) == "secret-1")

        KeychainHelper.delete(account: account)
        #expect(KeychainHelper.get(account: account) == nil)
    }

    @Test func set_existingItem_updatesValue() {
        let account = Self.makeAccount()
        defer { KeychainHelper.delete(account: account) }

        #expect(KeychainHelper.set(account: account, value: "original"))
        #expect(KeychainHelper.set(account: account, value: "updated"))
        #expect(KeychainHelper.get(account: account) == "updated")
    }

    @Test func delete_nonexistent_noCrash() {
        // Deleting something that was never stored must be a silent no-op.
        KeychainHelper.delete(account: Self.makeAccount())
    }

    @Test func get_nonexistent_returnsNil() {
        #expect(KeychainHelper.get(account: Self.makeAccount()) == nil)
    }

    // MARK: - OAuthTokenStorage

    @Test func saveLoad_roundtrip_accessTokenNeverPersisted() {
        let accountId = Self.makeAccount()
        defer { OAuthTokenStorage.delete(for: accountId) }

        let expires = Date().addingTimeInterval(3_600)
        OAuthTokenStorage.save(
            OAuthTokenStorage.AccountTokens(
                accessToken: "memory-only-token",
                refreshToken: "refresh-1",
                expiresAt: expires
            ),
            for: accountId
        )

        let loaded = OAuthTokenStorage.load(for: accountId)
        #expect(loaded.refreshToken == "refresh-1")
        // Access token is memory-only by design — load must never return one.
        #expect(loaded.accessToken == nil)
        #expect(loaded.expiresAt != nil)
        if let loadedExpires = loaded.expiresAt {
            #expect(abs(loadedExpires.timeIntervalSince1970 - expires.timeIntervalSince1970) < 1)
        }
    }

    @Test func perAccountIsolation() {
        let accountA = Self.makeAccount()
        let accountB = Self.makeAccount()
        defer {
            OAuthTokenStorage.delete(for: accountA)
            OAuthTokenStorage.delete(for: accountB)
        }

        OAuthTokenStorage.save(
            OAuthTokenStorage.AccountTokens(accessToken: nil, refreshToken: "refresh-a", expiresAt: nil),
            for: accountA
        )
        OAuthTokenStorage.save(
            OAuthTokenStorage.AccountTokens(accessToken: nil, refreshToken: "refresh-b", expiresAt: nil),
            for: accountB
        )

        #expect(OAuthTokenStorage.load(for: accountA).refreshToken == "refresh-a")
        #expect(OAuthTokenStorage.load(for: accountB).refreshToken == "refresh-b")

        // Deleting one account must not touch the other.
        OAuthTokenStorage.delete(for: accountA)
        #expect(OAuthTokenStorage.load(for: accountA).refreshToken == nil)
        #expect(OAuthTokenStorage.load(for: accountB).refreshToken == "refresh-b")
    }

    @Test func delete_clearsRefreshTokenAndExpiry() {
        let accountId = Self.makeAccount()

        OAuthTokenStorage.save(
            OAuthTokenStorage.AccountTokens(
                accessToken: nil,
                refreshToken: "refresh-1",
                expiresAt: Date().addingTimeInterval(3_600)
            ),
            for: accountId
        )
        OAuthTokenStorage.delete(for: accountId)

        let loaded = OAuthTokenStorage.load(for: accountId)
        #expect(loaded.refreshToken == nil)
        #expect(loaded.expiresAt == nil)
    }

    @Test func save_withoutRefreshToken_keepsExistingEntry() {
        // save() only writes fields that are present — a nil refresh token must
        // not clear a previously stored one (matches refresh-cycle behavior
        // where only the expiry advances).
        let accountId = Self.makeAccount()
        defer { OAuthTokenStorage.delete(for: accountId) }

        OAuthTokenStorage.save(
            OAuthTokenStorage.AccountTokens(accessToken: nil, refreshToken: "refresh-keep", expiresAt: nil),
            for: accountId
        )
        OAuthTokenStorage.save(
            OAuthTokenStorage.AccountTokens(accessToken: nil, refreshToken: nil, expiresAt: Date()),
            for: accountId
        )

        #expect(OAuthTokenStorage.load(for: accountId).refreshToken == "refresh-keep")
    }
}
