import Foundation
import Testing
@testable import AIBatteryCore

/// A Keychain the test controls: what is stored, which reads fail, and how often each item is read.
private final class FakeKeychain: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: String] = [:]
    private var readFailures: [String: OSStatus] = [:]
    private var readCounts: [String: Int] = [:]
    private var writesFail = false
    private var writesAreCorrupted = false
    private var refusedDeletes: Set<String> = []
    private var onRead: (@Sendable (String) -> Void)?
    private var onWrite: (@Sendable () -> Void)?

    var access: KeychainAccess {
        KeychainAccess(
            read: { [self] name in
                let (hook, failure, value) = lock.withLock {
                    readCounts[name, default: 0] += 1
                    return (onRead, readFailures[name], items[name])
                }
                hook?(name)
                if let failure {
                    return .failed(failure)
                }
                return value.map { .found($0) } ?? .notFound
            },
            set: { [self] name, value in
                lock.withLock { onWrite }?()
                return lock.withLock {
                    guard !writesFail else { return false }
                    items[name] = writesAreCorrupted ? String(value.dropLast()) : value
                    return true
                }
            },
            delete: { [self] name in
                lock.withLock {
                    guard !refusedDeletes.contains(name) else { return false }
                    items[name] = nil
                    return true
                }
            }
        )
    }

    func put(_ value: String, in name: String) {
        lock.withLock { items[name] = value }
    }

    func item(_ name: String) -> String? {
        lock.withLock { items[name] }
    }

    func itemNames() -> [String] {
        lock.withLock { items.keys.sorted() }
    }

    func reads(of name: String) -> Int {
        lock.withLock { readCounts[name, default: 0] }
    }

    func failReads(of name: String, with status: OSStatus?) {
        lock.withLock { readFailures[name] = status }
    }

    func failWrites(_ fail: Bool) {
        lock.withLock { writesFail = fail }
    }

    /// A write that reports success and stores something else.
    func corruptWrites(_ corrupt: Bool) {
        lock.withLock { writesAreCorrupted = corrupt }
    }

    /// What macOS does to a build the item has not approved.
    func refuseDeletes(of name: String) {
        lock.withLock { _ = refusedDeletes.insert(name) }
    }

    func holdReads(_ hook: (@Sendable (String) -> Void)?) {
        lock.withLock { onRead = hook }
    }

    func holdWrites(_ hook: (@Sendable () -> Void)?) {
        lock.withLock { onWrite = hook }
    }

    /// The vault item decoded, or nil when there is no item.
    func vault() -> [String: String]? {
        item(RefreshTokenVault.itemName).flatMap { try? JSONDecoder().decode([String: String].self, from: Data($0.utf8)) }
    }

    func putVault(_ entries: [String: String]) throws {
        let data = try JSONEncoder().encode(entries)
        try put(#require(String(data: data, encoding: .utf8)), in: RefreshTokenVault.itemName)
    }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_800_000_000)

    func now() -> Date {
        lock.withLock { date }
    }

    func advance(_ seconds: TimeInterval) {
        lock.withLock { date += seconds }
    }
}

private final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: KeychainHelper.ReadResult?

    var value: KeychainHelper.ReadResult? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

@Suite("RefreshTokenVault")
struct RefreshTokenVaultTests {
    private let keychain = FakeKeychain()
    private let clock = TestClock()
    private let item = RefreshTokenVault.itemName

    private func makeVault() -> RefreshTokenVault {
        RefreshTokenVault(keychain: keychain.access, now: { [clock] in clock.now() })
    }

    // MARK: - One item

    /// The point of the type: N accounts, one Keychain item, so one prompt per app update.
    @Test func everyAccountLivesInOneItem() {
        let vault = makeVault()
        vault.set("token-a", for: "org-a")
        vault.set("token-b", for: "codex_b")

        #expect(keychain.itemNames() == [item])
        #expect(keychain.vault() == ["org-a": "token-a", "codex_b": "token-b"])
        #expect(vault.token(for: "org-a") == .found("token-a"))
        #expect(vault.token(for: "codex_b") == .found("token-b"))
        #expect(vault.token(for: "nobody") == .notFound)
    }

    @Test func theItemIsReadOncePerProcess() throws {
        try keychain.putVault(["a": "A", "b": "B"])
        let vault = makeVault()

        #expect(vault.token(for: "a") == .found("A"))
        #expect(vault.token(for: "b") == .found("B"))
        #expect(vault.token(for: "a") == .found("A"))
        vault.set("A2", for: "a")

        #expect(keychain.reads(of: item) == 1)
        #expect(keychain.vault() == ["a": "A2", "b": "B"])
    }

    @Test func aFreshInstallWritesWithoutAnExistingItem() {
        let vault = makeVault()
        vault.set("first", for: "a")
        #expect(keychain.vault() == ["a": "first"])
    }

    @Test func removingTheLastTokenDeletesTheItem() throws {
        try keychain.putVault(["a": "A", "b": "B"])
        let vault = makeVault()

        vault.remove("a")
        #expect(keychain.vault() == ["b": "B"])
        #expect(vault.token(for: "a") == .notFound)

        vault.remove("b")
        #expect(keychain.item(item) == nil, "an empty item would still raise a prompt after an update")
    }

    @Test func anItemThatIsNotJSONIsTreatedAsEmptyAndReplaced() {
        keychain.put("not json", in: item)
        let vault = makeVault()

        #expect(vault.token(for: "a") == .notFound)
        vault.set("A", for: "a")
        #expect(keychain.vault() == ["a": "A"])
    }

    // MARK: - Adopting the pre-3.5 per-account items

    @Test func anOldPerAccountItemMovesIntoTheVault() {
        keychain.put("old-a", in: "refreshToken_org-a")
        keychain.put("old-b", in: "refreshToken_codex_b")
        let vault = makeVault()

        #expect(vault.token(for: "org-a") == .found("old-a"))
        #expect(vault.token(for: "codex_b") == .found("old-b"))

        #expect(keychain.vault() == ["org-a": "old-a", "codex_b": "old-b"])
        #expect(keychain.itemNames() == [item], "the old items are deleted once their tokens are in the vault")
    }

    /// Deleting the old item is the one destructive step, so a vault that did not take the
    /// token must leave it where it was for the next launch.
    @Test func theOldItemIsKeptWhenTheVaultWriteFails() {
        keychain.put("old-a", in: "refreshToken_a")
        keychain.failWrites(true)
        let vault = makeVault()

        #expect(vault.token(for: "a") == .found("old-a"), "the token is still usable this session")
        #expect(keychain.item("refreshToken_a") == "old-a")
        #expect(keychain.item(item) == nil)
    }

    @Test func anOldItemThatCannotBeReadReportsTheFailure() {
        keychain.put("old-a", in: "refreshToken_a")
        keychain.failReads(of: "refreshToken_a", with: errSecAuthFailed)
        let vault = makeVault()

        #expect(vault.token(for: "a") == .failed(errSecAuthFailed))
        #expect(keychain.item("refreshToken_a") == "old-a")
    }

    /// A leftover old item holds a token that has since been rotated. Reading it would
    /// raise a prompt and hand back a dead token.
    @Test func theVaultWinsOverALeftoverOldItem() throws {
        try keychain.putVault(["a": "current"])
        keychain.put("stale", in: "refreshToken_a")
        let vault = makeVault()

        #expect(vault.token(for: "a") == .found("current"))
        #expect(keychain.reads(of: "refreshToken_a") == 0)
    }

    /// Sign-out must remove the old item too, or the next launch would adopt it and the
    /// account the user signed out of would be signed in again.
    @Test func removeAlsoDeletesTheOldItem() throws {
        try keychain.putVault(["a": "current", "b": "B"])
        keychain.put("stale", in: "refreshToken_a")
        let vault = makeVault()

        vault.remove("a")

        #expect(keychain.item("refreshToken_a") == nil)
        #expect(makeVault().token(for: "a") == .notFound, "a new process finds nothing to adopt")
    }

    // MARK: - An unreadable vault

    /// One Deny must answer every account. Before, each account's own item raised its own prompt.
    @Test func oneFailedReadAnswersEveryAccount() throws {
        try keychain.putVault(["a": "A", "b": "B", "c": "C"])
        keychain.put("old-d", in: "refreshToken_d")
        keychain.failReads(of: item, with: errSecAuthFailed)
        let vault = makeVault()

        for key in ["a", "b", "c", "d"] {
            #expect(vault.token(for: key) == .failed(errSecAuthFailed))
        }
        #expect(keychain.reads(of: item) == 1)
        #expect(keychain.reads(of: "refreshToken_d") == 0, "old items are not tried while the vault is unreadable")
    }

    @Test func aFailedReadIsRetriedOnceTheWindowHasPassed() throws {
        try keychain.putVault(["a": "A"])
        keychain.failReads(of: item, with: errSecInteractionNotAllowed)
        let vault = makeVault()
        #expect(vault.token(for: "a") == .failed(errSecInteractionNotAllowed))

        keychain.failReads(of: item, with: nil)
        clock.advance(RefreshTokenVault.failureShareWindow - 1)
        #expect(vault.token(for: "a") == .failed(errSecInteractionNotAllowed), "still inside the window")

        clock.advance(2)
        #expect(vault.token(for: "a") == .found("A"))
        #expect(keychain.reads(of: item) == 2)
    }

    /// A write replaces the whole item. Writing before a read has succeeded would destroy
    /// the tokens of every account this process has not seen.
    @Test func aChangeMadeWhileUnreadableWaitsAndNeverReplacesTheItem() throws {
        try keychain.putVault(["a": "A", "b": "B"])
        keychain.failReads(of: item, with: errSecInteractionNotAllowed)
        let vault = makeVault()
        #expect(vault.token(for: "a") == .failed(errSecInteractionNotAllowed))

        vault.set("C", for: "c")
        vault.remove("b")
        #expect(keychain.vault() == ["a": "A", "b": "B"], "nothing is written while the vault is unread")
        #expect(keychain.reads(of: item) == 1, "a write must not repeat a failed read: it could prompt on the main thread")

        keychain.failReads(of: item, with: nil)
        clock.advance(RefreshTokenVault.failureShareWindow + 1)
        #expect(vault.token(for: "c") == .found("C"))
        #expect(keychain.vault() == ["a": "A", "c": "C"], "the waiting changes are applied to what was read")
    }

    /// A read can sit on a Keychain prompt for minutes. Sign-in and sign-out run on the main
    /// thread and must not wait behind it.
    @Test func aChangeDoesNotWaitBehindAReadThatIsStillPrompting() throws {
        try keychain.putVault(["a": "A"])
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        keychain.holdReads { [item] name in
            guard name == item else { return }
            entered.signal()
            release.wait()
        }
        let vault = makeVault()

        let readDone = DispatchSemaphore(value: 0)
        Thread { [vault] in
            _ = vault.token(for: "a")
            readDone.signal()
        }.start()
        entered.wait()

        let changeDone = DispatchSemaphore(value: 0)
        Thread { [vault] in
            vault.set("B", for: "b")
            changeDone.signal()
        }.start()
        #expect(changeDone.wait(timeout: .now() + 5) == .success, "set() blocked behind the prompting read")
        #expect(keychain.vault() == ["a": "A"])

        keychain.holdReads(nil)
        release.signal()
        readDone.wait()
        #expect(vault.token(for: "b") == .found("B"))
        #expect(keychain.vault() == ["a": "A", "b": "B"])
    }

    // MARK: - Found in review

    /// Blocks the first read of `name` until `release` is signalled; `entered` fires when it starts.
    private func hold(_ name: String) -> (entered: DispatchSemaphore, release: DispatchSemaphore) {
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        keychain.holdReads { read in
            guard read == name else { return }
            entered.signal()
            release.wait()
        }
        return (entered, release)
    }

    /// Runs `change` on its own thread and reports whether it returned within five seconds.
    private func returnsPromptly(_ change: @escaping @Sendable () -> Void) -> Bool {
        let done = DispatchSemaphore(value: 0)
        Thread {
            change()
            done.signal()
        }.start()
        return done.wait(timeout: .now() + 5) == .success
    }

    /// The old item's read can sit on a prompt while the user signs in afresh. That sign-in
    /// was only queued, the old token was then written, and a quit before the next vault
    /// operation brought the old token back on the next launch.
    @Test func aSignInMadeWhileAnOldItemIsBeingReadIsNotOverwrittenByIt() {
        keychain.put("old", in: "refreshToken_a")
        let gate = hold("refreshToken_a")
        let vault = makeVault()

        let result = ResultBox()
        let readDone = DispatchSemaphore(value: 0)
        Thread { [vault] in
            result.value = vault.token(for: "a")
            readDone.signal()
        }.start()
        gate.entered.wait()

        let signedIn = returnsPromptly { [vault] in vault.set("NEW", for: "a") }
        #expect(signedIn, "set() blocked behind the prompting read")

        keychain.holdReads(nil)
        gate.release.signal()
        readDone.wait()

        #expect(result.value == .found("NEW"))
        #expect(keychain.vault() == ["a": "NEW"], "written before the read returns, not at some later operation")
        #expect(makeVault().token(for: "a") == .found("NEW"), "the next launch sees the new sign-in")
    }

    @Test func aSignOutMadeWhileAnOldItemIsBeingReadWins() {
        keychain.put("old", in: "refreshToken_a")
        let gate = hold("refreshToken_a")
        let vault = makeVault()

        let result = ResultBox()
        let readDone = DispatchSemaphore(value: 0)
        Thread { [vault] in
            result.value = vault.token(for: "a")
            readDone.signal()
        }.start()
        gate.entered.wait()

        let signedOut = returnsPromptly { [vault] in vault.remove("a") }
        #expect(signedOut, "remove() blocked behind the prompting read")

        keychain.holdReads(nil)
        gate.release.signal()
        readDone.wait()

        #expect(result.value == .notFound)
        #expect(makeVault().token(for: "a") == .notFound, "the next launch must not find the signed-out account")
    }

    /// A change that finds the vault busy is queued. If the busy operation has already taken
    /// its last look at the queue, nothing else would ever write the change: the app could
    /// quit hours later with a sign-in that was never saved.
    @Test func aQueuedChangeIsWrittenAsSoonAsTheVaultIsFree() throws {
        try keychain.putVault(["a": "A"])
        let vault = makeVault()
        #expect(vault.token(for: "a") == .found("A"))

        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        keychain.holdWrites {
            entered.signal()
            release.wait()
        }
        Thread { [vault] in vault.set("B", for: "b") }.start()
        entered.wait()

        // The first write is in progress and has already emptied the queue.
        let queued = returnsPromptly { [vault] in vault.set("C", for: "c") }
        #expect(queued, "set() blocked behind a write in progress")

        keychain.holdWrites(nil)
        release.signal()

        let expected = ["a": "A", "b": "B", "c": "C"]
        for _ in 0..<500 where keychain.vault() != expected {
            usleep(10_000)
        }
        #expect(keychain.vault() == expected, "no further call was made on the vault")
    }

    /// macOS refuses a delete from a build the old item has not approved. The vault entry
    /// went, the leftover stayed, and the next lookup adopted it.
    @Test func aRemovalSticksWhenTheOldItemCannotBeDeleted() throws {
        try keychain.putVault(["a": "current", "b": "B"])
        keychain.put("stale", in: "refreshToken_a")
        keychain.refuseDeletes(of: "refreshToken_a")
        let vault = makeVault()

        vault.remove("a")

        #expect(vault.token(for: "a") == .notFound)
        #expect(makeVault().token(for: "a") == .notFound, "nor on the next launch")
        #expect(keychain.item("refreshToken_a") == "stale", "the leftover is still there")
        #expect(keychain.reads(of: "refreshToken_a") == 0, "and is never read")
        #expect(vault.token(for: "b") == .found("B"))

        // Signing in again replaces the marker.
        vault.set("fresh", for: "a")
        #expect(makeVault().token(for: "a") == .found("fresh"))
    }

    /// Found in the second review: with one account left, a refused delete of the item
    /// itself left that account's token in it, and the next launch read it back.
    @Test func removingTheLastTokenEmptiesAnItemThatCannotBeDeleted() throws {
        try keychain.putVault(["a": "A"])
        keychain.refuseDeletes(of: item)
        let vault = makeVault()

        vault.remove("a")

        #expect(keychain.vault() == [:], "the item is still there, with no token in it")
        #expect(makeVault().token(for: "a") == .notFound, "the next launch must not find the signed-out account")
    }

    /// A write that reports success is not enough to delete the only other copy.
    @Test func theOldItemIsKeptWhenTheVaultDoesNotReadBackWhatWasWritten() {
        keychain.put("old-a", in: "refreshToken_a")
        keychain.corruptWrites(true)
        let vault = makeVault()

        #expect(vault.token(for: "a") == .found("old-a"))
        #expect(keychain.item("refreshToken_a") == "old-a")
    }

    /// A failed write loses that one change if the app quits, and nothing else. The next
    /// write that succeeds carries everything in memory.
    @Test func aFailedWriteIsCaughtUpByTheNextOne() throws {
        try keychain.putVault(["a": "A"])
        let vault = makeVault()
        #expect(vault.token(for: "a") == .found("A"))

        keychain.failWrites(true)
        vault.set("A2", for: "a")
        #expect(keychain.vault() == ["a": "A"])
        #expect(makeVault().token(for: "a") == .found("A"), "a quit now would lose the rotation, as it always has")

        keychain.failWrites(false)
        vault.set("B", for: "b")
        #expect(keychain.vault() == ["a": "A2", "b": "B"])
    }

    // MARK: - The real Keychain, and who may open the app's item

    /// One round trip through the real Keychain under a throwaway item name.
    @Test func roundTripThroughTheRealKeychain() {
        // Unique item and key names: `remove` also deletes `refreshToken_<key>`, and that
        // must never be the name of an item the installed app owns.
        let run = UUID().uuidString
        let name = "test-vault-\(run)"
        let keyA = "test-key-a-\(run)"
        let keyB = "test-key-b-\(run)"
        defer { KeychainHelper.delete(account: name) }

        let vault = RefreshTokenVault(keychain: .system, itemName: name)
        vault.set("token-a", for: keyA)
        vault.set("token-b", for: keyB)

        let reopened = RefreshTokenVault(keychain: .system, itemName: name)
        #expect(reopened.token(for: keyA) == .found("token-a"))
        #expect(reopened.token(for: keyB) == .found("token-b"))

        reopened.remove(keyA)
        reopened.remove(keyB)
        #expect(KeychainHelper.read(account: name) == .notFound)
    }

    /// `shared` opens the real item only when the process is the app, decided by bundle id.
    /// If the id in Info.plist ever stopped matching, the released app would keep tokens in
    /// memory only and sign everyone out at every launch.
    @Test func theAppBundleIdentifierMatchesInfoPlist() throws {
        let plistURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("AIBattery/Info.plist")
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: plistURL), format: nil)
        let identifier = try #require((plist as? [String: Any])?["CFBundleIdentifier"] as? String)
        #expect(identifier == RefreshTokenVault.appBundleIdentifier)
    }

    /// The test runner is not the app, so `shared` is the in-memory store here. This test
    /// deliberately does not look at the real item: reading it would raise a prompt on a
    /// Mac that has the app installed.
    @Test func aTestProcessIsNotTheApp() {
        #expect(Bundle.main.bundleIdentifier != RefreshTokenVault.appBundleIdentifier)
    }
}
