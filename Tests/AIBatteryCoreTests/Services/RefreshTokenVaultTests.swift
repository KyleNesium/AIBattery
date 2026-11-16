import Foundation
import Testing
@testable import AIBatteryCore

/// A Keychain the test controls: what is stored, which reads fail, and how often each item is read.
private final class FakeKeychain: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: String] = [:]
    private var readFailures: [String: OSStatus] = [:]
    private var readCounts: [String: Int] = [:]
    private var writeCount = 0
    private var writeFailure: OSStatus?
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
                    writeCount += 1
                    if let writeFailure {
                        return writeFailure
                    }
                    items[name] = writesAreCorrupted ? String(value.dropLast()) : value
                    return errSecSuccess
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

    /// Write attempts, successful or not.
    var writes: Int {
        lock.withLock { writeCount }
    }

    func failReads(of name: String, with status: OSStatus?) {
        lock.withLock { readFailures[name] = status }
    }

    /// `status` defaults to what the Keychain returns when it cannot show a prompt (dark wake).
    func failWrites(_ fail: Bool, status: OSStatus = errSecInteractionNotAllowed) {
        lock.withLock { writeFailure = fail ? status : nil }
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

/// Stands in for the retry timer: collects what the vault schedules so a test can run it.
private final class RetryQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var scheduled: [(delay: TimeInterval, work: @Sendable () -> Void)] = []

    func add(_ delay: TimeInterval, _ work: @escaping @Sendable () -> Void) {
        lock.withLock { scheduled.append((delay, work)) }
    }

    var delays: [TimeInterval] {
        lock.withLock { scheduled.map(\.delay) }
    }

    /// Runs the oldest scheduled retry, as the timer would.
    func fireNext() {
        let next = lock.withLock { scheduled.isEmpty ? nil : scheduled.removeFirst() }
        next?.work()
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
    private let retries = RetryQueue()
    private let item = RefreshTokenVault.itemName

    private func makeVault() -> RefreshTokenVault {
        RefreshTokenVault(
            keychain: keychain.access,
            now: { [clock] in clock.now() },
            schedule: { [retries] delay, work in retries.add(delay, work) }
        )
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
            _ = release.wait(timeout: .now() + 10)
        }
        let vault = makeVault()

        let readDone = DispatchSemaphore(value: 0)
        Thread { [vault] in
            _ = vault.token(for: "a")
            readDone.signal()
        }.start()
        #expect(entered.wait(timeout: .now() + 5) == .success, "the hooked operation never ran")

        let changeDone = DispatchSemaphore(value: 0)
        Thread { [vault] in
            vault.set("B", for: "b")
            changeDone.signal()
        }.start()
        #expect(changeDone.wait(timeout: .now() + 5) == .success, "set() blocked behind the prompting read")
        #expect(keychain.vault() == ["a": "A"])

        keychain.holdReads(nil)
        release.signal()
        #expect(readDone.wait(timeout: .now() + 5) == .success, "the hooked operation never ran")
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
            _ = release.wait(timeout: .now() + 10)
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
        #expect(gate.entered.wait(timeout: .now() + 5) == .success, "the hooked operation never ran")

        let signedIn = returnsPromptly { [vault] in vault.set("NEW", for: "a") }
        #expect(signedIn, "set() blocked behind the prompting read")

        keychain.holdReads(nil)
        gate.release.signal()
        #expect(readDone.wait(timeout: .now() + 5) == .success, "the hooked operation never ran")

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
        #expect(gate.entered.wait(timeout: .now() + 5) == .success, "the hooked operation never ran")

        let signedOut = returnsPromptly { [vault] in vault.remove("a") }
        #expect(signedOut, "remove() blocked behind the prompting read")

        keychain.holdReads(nil)
        gate.release.signal()
        #expect(readDone.wait(timeout: .now() + 5) == .success, "the hooked operation never ran")

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
            _ = release.wait(timeout: .now() + 10)
        }
        let firstWriteDone = DispatchSemaphore(value: 0)
        Thread { [vault] in
            vault.set("B", for: "b")
            firstWriteDone.signal()
        }.start()
        #expect(entered.wait(timeout: .now() + 5) == .success, "the hooked operation never ran")

        // The first write is in progress and has already emptied the queue.
        let queued = returnsPromptly { [vault] in vault.set("C", for: "c") }
        #expect(queued, "set() blocked behind a write in progress")
        #expect(retries.delays == [0], "a flush is scheduled for when the vault is free")

        keychain.holdWrites(nil)
        release.signal()
        #expect(firstWriteDone.wait(timeout: .now() + 5) == .success, "the hooked operation never ran")
        #expect(keychain.vault() == ["a": "A", "b": "B"])

        retries.fireNext()
        #expect(keychain.vault() == ["a": "A", "b": "B", "c": "C"], "no further call was made on the vault")
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

    /// Found in the third review: a write that failed was logged and forgotten. A sign-in on
    /// an account whose token never rotates (an API key) was then never saved, however long
    /// the app ran, and a quit lost it.
    @Test func aFailedWriteIsRetriedOnItsOwn() throws {
        try keychain.putVault(["a": "A"])
        let vault = makeVault()
        #expect(vault.token(for: "a") == .found("A"))

        keychain.failWrites(true)
        vault.set("B", for: "b")
        #expect(keychain.vault() == ["a": "A"])
        #expect(retries.delays == [RefreshTokenVault.firstRetryDelay], "one retry is scheduled")

        // Still failing: the retry backs off instead of giving up.
        retries.fireNext()
        #expect(keychain.vault() == ["a": "A"])
        #expect(retries.delays == [RefreshTokenVault.firstRetryDelay * 2])

        // The Keychain recovers. No token changes; the retry alone saves the sign-in.
        keychain.failWrites(false)
        retries.fireNext()
        #expect(keychain.vault() == ["a": "A", "b": "B"])
        #expect(retries.delays.isEmpty, "nothing left to retry")
        #expect(makeVault().token(for: "b") == .found("B"), "the next launch has the sign-in")
    }

    /// A cancelled or denied prompt is a refusal. A timer that wrote again would raise that
    /// prompt again, every few minutes, on its own. The next vault call still retries.
    @Test func aRefusedWriteIsNotRetriedOnATimer() throws {
        try keychain.putVault(["a": "A"])
        let vault = makeVault()
        #expect(vault.token(for: "a") == .found("A"))

        for refusal in [errSecUserCanceled, errSecAuthFailed] {
            keychain.failWrites(true, status: refusal)
            vault.set("B", for: "b")
            #expect(retries.delays.isEmpty, "status \(refusal) must not start a timer")
        }

        keychain.failWrites(false)
        #expect(vault.token(for: "a") == .found("A"))
        #expect(keychain.vault() == ["a": "A", "b": "B"], "the next vault call saves it")
    }

    /// Found in the fourth review: a retry already on the timer survived a later refusal
    /// and wrote again, which can raise the prompt the user had just declined.
    @Test func aTimerAlreadyRunningDoesNotWriteAfterARefusal() throws {
        try keychain.putVault(["a": "A"])
        let vault = makeVault()
        #expect(vault.token(for: "a") == .found("A"))

        keychain.failWrites(true)
        vault.set("B", for: "b")
        #expect(retries.delays.count == 1, "the failed write put a retry on the timer")

        keychain.failWrites(true, status: errSecUserCanceled)
        vault.set("C", for: "c")
        let writesBeforeTheTimer = keychain.writes

        retries.fireNext()
        #expect(keychain.writes == writesBeforeTheTimer, "the timer wrote after the user refused")
    }

    /// Found in the fourth review: a change made while the vault could not be read waited
    /// for a read that nothing else might ever make. With no unreadable account left to
    /// drive one, a sign-in was never saved, and a quit lost it.
    @Test func aChangeWaitingOnAnUnreadVaultRetriesTheReadItself() throws {
        try keychain.putVault(["a": "A"])
        keychain.failReads(of: item, with: errSecInteractionNotAllowed)
        let vault = makeVault()
        #expect(vault.token(for: "a") == .failed(errSecInteractionNotAllowed))

        vault.set("B", for: "b")
        #expect(retries.delays.count == 1, "a retry is on the timer")

        // Still unreadable: the retry backs off instead of giving up.
        clock.advance(RefreshTokenVault.failureShareWindow + 1)
        retries.fireNext()
        #expect(retries.delays.count == 1)
        #expect(keychain.vault() == ["a": "A"], "nothing is written while the vault is unread")

        // The Keychain becomes readable. No account asks for its token; the retry alone saves the sign-in.
        keychain.failReads(of: item, with: nil)
        clock.advance(RefreshTokenVault.failureShareWindow + 1)
        retries.fireNext()
        #expect(keychain.vault() == ["a": "A", "b": "B"])
        #expect(makeVault().token(for: "b") == .found("B"), "the next launch has the sign-in")
    }

    /// A change can arrive while a read is waiting on a prompt. If that read then fails, the
    /// change is still waiting and the reader has gone; something must put a retry on the timer.
    @Test func aChangeMadeDuringAReadThatThenFailsIsStillRetried() throws {
        try keychain.putVault(["a": "A"])
        keychain.failReads(of: item, with: errSecInteractionNotAllowed)
        let gate = hold(item)
        let vault = makeVault()

        let readDone = DispatchSemaphore(value: 0)
        Thread { [vault] in
            _ = vault.token(for: "a")
            readDone.signal()
        }.start()
        #expect(gate.entered.wait(timeout: .now() + 5) == .success, "the hooked operation never ran")

        let queued = returnsPromptly { [vault] in vault.set("B", for: "b") }
        #expect(queued, "set() blocked behind the prompting read")

        keychain.holdReads(nil)
        gate.release.signal()
        #expect(readDone.wait(timeout: .now() + 5) == .success, "the hooked operation never ran")

        #expect(retries.delays == [0], "a flush is scheduled for when the vault is free")
        retries.fireNext()
        #expect(retries.delays == [RefreshTokenVault.firstRetryDelay], "the queued sign-in was left with nothing to retry it")
        #expect(keychain.vault() == ["a": "A"], "and nothing was written to a vault that was never read")
    }

    /// After Deny or Cancel on the read prompt nothing may read again by itself: not a timer
    /// started by a change, and not one that was already running.
    @Test func aRefusedReadIsNeverRepeatedByATimer() throws {
        try keychain.putVault(["a": "A"])
        keychain.failReads(of: item, with: errSecInteractionNotAllowed)
        let vault = makeVault()
        #expect(vault.token(for: "a") == .failed(errSecInteractionNotAllowed))
        vault.set("B", for: "b")
        #expect(retries.delays.count == 1, "a retry is on the timer from the first, passing failure")

        // The user is asked again and says no.
        keychain.failReads(of: item, with: errSecAuthFailed)
        clock.advance(RefreshTokenVault.failureShareWindow + 1)
        #expect(vault.token(for: "a") == .failed(errSecAuthFailed))
        let readsAfterTheRefusal = keychain.reads(of: item)

        // The timer that was already running fires long after; a new change arrives too.
        clock.advance(600)
        retries.fireNext()
        vault.set("C", for: "c")
        retries.fireNext()

        #expect(keychain.reads(of: item) == readsAfterTheRefusal, "something read the item again on its own")
        #expect(retries.delays.isEmpty, "and nothing is left on the timer")
    }

    /// Found in the sixth review: a change that arrived while a write was in progress
    /// scheduled a flush. The write was refused, and the flush then wrote again by itself,
    /// which can raise the prompt the user had just declined.
    @Test func aFlushDoesNotWriteAgainAfterARefusal() throws {
        try keychain.putVault(["a": "A"])
        let vault = makeVault()
        #expect(vault.token(for: "a") == .found("A"))

        keychain.failWrites(true, status: errSecUserCanceled)
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        keychain.holdWrites {
            entered.signal()
            _ = release.wait(timeout: .now() + 10)
        }
        let firstWriteDone = DispatchSemaphore(value: 0)
        Thread { [vault] in
            vault.set("B", for: "b")
            firstWriteDone.signal()
        }.start()
        #expect(entered.wait(timeout: .now() + 5) == .success, "the hooked operation never ran")

        let queued = returnsPromptly { [vault] in vault.set("C", for: "c") }
        #expect(queued, "set() blocked behind a write in progress")

        keychain.holdWrites(nil)
        release.signal()
        #expect(firstWriteDone.wait(timeout: .now() + 5) == .success, "the hooked operation never ran")
        let writesAfterTheRefusal = keychain.writes

        retries.fireNext()
        #expect(keychain.writes == writesAfterTheRefusal, "the flush wrote after the user refused")

        // The next change the user makes carries everything.
        keychain.failWrites(false)
        vault.set("D", for: "d")
        #expect(keychain.vault() == ["a": "A", "b": "B", "c": "C", "d": "D"])
    }

    // MARK: - copy: all or nothing, for an account changing id

    @Test func copyStoresTheTokenUnderBothKeysInOneWrite() throws {
        try keychain.putVault(["pending": "T", "other": "O"])
        let vault = makeVault()
        #expect(vault.token(for: "pending") == .found("T"))
        let writesBefore = keychain.writes

        #expect(vault.copy(from: "pending", to: "org") == true)

        #expect(keychain.writes == writesBefore + 1)
        #expect(keychain.vault() == ["pending": "T", "org": "T", "other": "O"])
        #expect(makeVault().token(for: "org") == .found("T"))
    }

    /// Found in the fifth and sixth reviews. A copy that does not land must leave nothing
    /// behind: not in memory, not queued, not on the timer. Otherwise it lands later, on a
    /// key that may belong to another account, after the caller has given up on it.
    @Test func aCopyThatCannotBeWrittenLeavesNothingBehind() throws {
        try keychain.putVault(["pending": "T", "org": "ORIGINAL"])
        let vault = makeVault()
        #expect(vault.token(for: "pending") == .found("T"))

        keychain.failWrites(true)
        #expect(vault.copy(from: "pending", to: "org") == false)
        #expect(vault.copy(from: "pending", to: "new-org") == false)

        #expect(vault.token(for: "org") == .found("ORIGINAL"), "the destination's own token was replaced in memory")
        #expect(vault.token(for: "new-org") == .notFound)
        #expect(retries.delays.isEmpty, "nothing may be left to retry")

        // Writes work again, and the pending account is signed out. Nothing from the
        // abandoned copies may reach the Keychain.
        keychain.failWrites(false)
        vault.remove("pending")
        #expect(keychain.vault() == ["org": "ORIGINAL"])
    }

    @Test func copyRefusesRatherThanWaits() throws {
        // Unread: no read is made on the caller's behalf, and nothing is queued.
        try keychain.putVault(["pending": "T"])
        keychain.failReads(of: item, with: errSecInteractionNotAllowed)
        let unread = makeVault()
        #expect(unread.token(for: "pending") == .failed(errSecInteractionNotAllowed))
        let readsBefore = keychain.reads(of: item)
        #expect(unread.copy(from: "pending", to: "org") == false)
        #expect(keychain.reads(of: item) == readsBefore)
        #expect(retries.delays.isEmpty)

        // Nothing stored under the source.
        keychain.failReads(of: item, with: nil)
        let vault = makeVault()
        #expect(vault.copy(from: "nobody", to: "org") == false)

        // Memory ahead of the Keychain: the copy's own visit saves what was waiting first,
        // so the token it copies is one the Keychain holds.
        keychain.failWrites(true)
        vault.set("NEW", for: "pending")
        keychain.failWrites(false)
        #expect(vault.copy(from: "pending", to: "org") == true)
        #expect(keychain.vault() == ["pending": "NEW", "org": "NEW"])
    }

    /// Any later visit to the vault is also a chance to save what an earlier write missed.
    @Test func aFailedWriteIsRetriedByTheNextRead() throws {
        try keychain.putVault(["a": "A"])
        let vault = makeVault()
        #expect(vault.token(for: "a") == .found("A"))

        keychain.failWrites(true)
        vault.set("B", for: "b")
        keychain.failWrites(false)

        #expect(vault.token(for: "a") == .found("A"))
        #expect(keychain.vault() == ["a": "A", "b": "B"])
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
