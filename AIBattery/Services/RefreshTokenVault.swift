import Foundation
import os

/// The three Keychain operations the vault needs, so a test can substitute a fake.
struct KeychainAccess: Sendable {
    var read: @Sendable (String) -> KeychainHelper.ReadResult
    var set: @Sendable (String, String) -> Bool
    var delete: @Sendable (String) -> Void

    static let system = KeychainAccess(
        read: { KeychainHelper.read(account: $0) },
        set: { KeychainHelper.set(account: $0, value: $1) },
        delete: { KeychainHelper.delete(account: $0) }
    )

    /// A private store that lives and dies with the process.
    static func inMemory() -> KeychainAccess {
        let store = MemoryStore()
        return KeychainAccess(
            read: { name in store.withItems { $0[name].map { .found($0) } ?? .notFound } },
            set: { name, value in
                store.withItems { $0[name] = value }
                return true
            },
            delete: { name in store.withItems { $0[name] = nil } }
        )
    }

    private final class MemoryStore: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String: String] = [:]

        func withItems<T>(_ body: (inout [String: String]) -> T) -> T {
            lock.withLock { body(&items) }
        }
    }
}

/// Every account's refresh token, in ONE Keychain item.
///
/// Why one item: macOS ties a Keychain item to the exact build that wrote it (the item's
/// `partition_id` is that build's code hash), so after every app update each item raises
/// its own password prompt. One item per account meant one prompt per account. One item
/// means one prompt, however many accounts there are.
///
/// The item holds a JSON object `{storage key: refresh token}`. The rules:
///
/// - **Read once.** The item is read on first use and kept in memory for the life of the
///   process, so later lookups cost no Keychain call and no prompt.
/// - **The vault wins.** A key the vault holds is never looked up anywhere else.
/// - **Old items are adopted.** A key the vault lacks is looked up in its pre-3.5 item
///   (`refreshToken_<key>`). A token found there moves into the vault and the old item is
///   deleted, but only once the vault write has read back correctly. This is the whole
///   migration; it needs no flag and repeats for any account that failed the first time.
/// - **Never write unread.** A write replaces the whole item, so writing before a read has
///   succeeded would destroy tokens this process has not seen. A change made while the
///   vault is unreadable waits in memory and is applied when a later read succeeds. It is
///   lost if the app quits first.
/// - **One answer per failure.** A failed read is reused for `failureShareWindow`, so one
///   Deny, or one prompt cancelled by sleep, answers every account instead of raising a
///   prompt for each.
final class RefreshTokenVault: @unchecked Sendable {
    static let itemName = "refreshTokens"
    static let failureShareWindow: TimeInterval = 5
    static let appBundleIdentifier = "com.KyleNesium.AIBattery"

    /// The real Keychain item is opened only by the app itself. Any other process that
    /// loads this module — the test runner above all — gets a private in-memory store, so
    /// a test can never read, raise a prompt for, or rewrite the tokens of the app
    /// installed on the same Mac. A test pins `appBundleIdentifier` to Info.plist.
    static let shared: RefreshTokenVault = {
        let isApp = Bundle.main.bundleIdentifier == appBundleIdentifier
        if !isApp {
            AppLogger.oauth.notice("Refresh tokens are kept in memory only: this process is not the app")
        }
        return RefreshTokenVault(keychain: isApp ? .system : .inMemory())
    }()

    private let keychain: KeychainAccess
    private let itemName: String
    private let now: @Sendable () -> Date

    /// Held across Keychain calls, which can block on a prompt. Guards `entries` and `lastFailure`.
    private let ioLock = NSLock()
    /// nil until a read has succeeded.
    private var entries: [String: String]?
    private var lastFailure: (status: OSStatus, at: Date)?

    /// Changes not yet in `entries`: a token to store, or nil to remove one. It has its own
    /// lock, never held across a Keychain call, so the main thread can record a change
    /// while a read is waiting on a prompt.
    private let pendingLock = NSLock()
    private var pending: [String: String?] = [:]

    init(keychain: KeychainAccess, itemName: String = RefreshTokenVault.itemName, now: @escaping @Sendable () -> Date = { Date() }) {
        self.keychain = keychain
        self.itemName = itemName
        self.now = now
    }

    static func legacyItemName(for key: String) -> String {
        "refreshToken_\(key)"
    }

    /// The refresh token stored for `key`. May block on a Keychain prompt.
    func token(for key: String) -> KeychainHelper.ReadResult {
        ioLock.lock()
        defer { ioLock.unlock() }
        if let status = load(retryingFailure: true) {
            return .failed(status)
        }
        applyPending()
        if let token = entries?[key] {
            return .found(token)
        }
        return adoptLegacyItem(for: key)
    }

    func set(_ token: String, for key: String) {
        change(key, to: token)
    }

    func remove(_ key: String) {
        // The old item goes too, or a sign-out could leave a token that the next launch adopts.
        keychain.delete(Self.legacyItemName(for: key))
        change(key, to: nil)
    }

    // MARK: - Internal

    private func change(_ key: String, to token: String?) {
        pendingLock.withLock { _ = pending.updateValue(token, forKey: key) }
        // Busy means a read is waiting on a prompt. The change stays in `pending`, and
        // whoever holds the lock next applies it.
        guard ioLock.try() else { return }
        defer { ioLock.unlock() }
        if load(retryingFailure: false) == nil {
            applyPending()
        }
    }

    /// Reads the item if it is not in memory yet. Returns nil once loaded, else the failure.
    /// A write passes `retryingFailure: false`: it must not repeat a read that already
    /// failed, because that could raise a prompt on the main thread.
    private func load(retryingFailure: Bool) -> OSStatus? {
        if entries != nil {
            return nil
        }
        if let failure = lastFailure,
           !retryingFailure || now().timeIntervalSince(failure.at) < Self.failureShareWindow {
            return failure.status
        }
        switch keychain.read(itemName) {
        case let .found(json):
            entries = Self.decode(json)
        case .notFound:
            entries = [:]
        case let .failed(status):
            lastFailure = (status, now())
            return status
        }
        lastFailure = nil
        return nil
    }

    /// Moves waiting changes into `entries` and writes the item. Needs `ioLock` and a loaded vault.
    private func applyPending() {
        let changes = pendingLock.withLock {
            let waiting = pending
            pending = [:]
            return waiting
        }
        guard !changes.isEmpty, var updated = entries else { return }
        for (key, token) in changes {
            updated[key] = token
        }
        entries = updated
        write()
    }

    /// Writes `entries` as the item and returns the JSON written, or nil if the write failed.
    /// A failed write leaves `entries` ahead of the Keychain; the next write catches up.
    @discardableResult
    private func write() -> String? {
        guard let entries else { return nil }
        if entries.isEmpty {
            // No tokens left: remove the item rather than keep an empty one to prompt for.
            keychain.delete(itemName)
            return ""
        }
        guard let json = Self.encode(entries), keychain.set(itemName, json) else {
            AppLogger.oauth.error("Keychain: writing the refresh-token item failed")
            return nil
        }
        return json
    }

    /// The old item is deleted only after the vault write has read back correctly: this is
    /// the one step that destroys the previous copy of a token.
    private func adoptLegacyItem(for key: String) -> KeychainHelper.ReadResult {
        let legacyName = Self.legacyItemName(for: key)
        let result = keychain.read(legacyName)
        guard case let .found(token) = result else { return result }
        entries?[key] = token
        if let json = write(), keychain.read(itemName) == .found(json) {
            keychain.delete(legacyName)
            AppLogger.oauth.info("Keychain: moved \(key, privacy: .public) into the single refresh-token item")
        } else {
            AppLogger.oauth.error("Keychain: could not move \(key, privacy: .public); its old item is kept")
        }
        return result
    }

    private static func encode(_ entries: [String: String]) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(entries)).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// An item that does not decode is treated as empty; the next write replaces it.
    private static func decode(_ json: String) -> [String: String] {
        guard let entries = try? JSONDecoder().decode([String: String].self, from: Data(json.utf8)) else {
            AppLogger.oauth.error("Keychain: the refresh-token item is not readable JSON; treating it as empty")
            return [:]
        }
        return entries
    }
}
