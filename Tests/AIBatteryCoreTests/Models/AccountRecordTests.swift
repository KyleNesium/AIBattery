import Foundation
import Testing
@testable import AIBatteryCore

@Suite("AccountRecord")
struct AccountRecordTests {

    @Test func isPendingIdentity_trueForPendingPrefix() {
        let record = AccountRecord(
            id: "pending-ABC123",
            displayName: nil,
            organizationName: nil,
            billingType: nil,
            addedAt: Date()
        )
        #expect(record.isPendingIdentity)
    }

    @Test func isPendingIdentity_falseForRealOrgId() {
        let record = AccountRecord(
            id: "org-abc123def456",
            displayName: "Kyle",
            organizationName: "Acme Corp",
            billingType: "pro",
            addedAt: Date()
        )
        #expect(!record.isPendingIdentity)
    }

    @Test func codable_roundTrip() throws {
        let original = AccountRecord(
            id: "org-test",
            displayName: "Test User",
            organizationName: "Test Org",
            billingType: "teams",
            addedAt: Date(timeIntervalSince1970: 1700000000)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AccountRecord.self, from: data)
        #expect(decoded == original)
    }

    @Test func codable_arrayRoundTrip() throws {
        let records = [
            AccountRecord(id: "org-1", displayName: "User 1", organizationName: "Org 1", billingType: "pro", addedAt: Date()),
            AccountRecord(id: "org-2", displayName: "User 2", organizationName: "Org 2", billingType: "teams", addedAt: Date()),
        ]
        let data = try JSONEncoder().encode(records)
        let decoded = try JSONDecoder().decode([AccountRecord].self, from: data)
        #expect(decoded.count == 2)
        #expect(decoded[0].id == "org-1")
        #expect(decoded[1].id == "org-2")
    }

    @Test func codable_nilFields() throws {
        let original = AccountRecord(
            id: "pending-xyz",
            displayName: nil,
            organizationName: nil,
            billingType: nil,
            addedAt: Date(timeIntervalSince1970: 1700000000)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AccountRecord.self, from: data)
        #expect(decoded == original)
        #expect(decoded.displayName == nil)
        #expect(decoded.organizationName == nil)
        #expect(decoded.billingType == nil)
    }

    @Test func equatable_sameIdEqual() {
        let a = AccountRecord(id: "org-1", displayName: "A", organizationName: nil, billingType: nil, addedAt: Date())
        let b = AccountRecord(id: "org-1", displayName: "A", organizationName: nil, billingType: nil, addedAt: a.addedAt)
        #expect(a == b)
    }

    @Test func equatable_differentIdNotEqual() {
        let now = Date()
        let a = AccountRecord(id: "org-1", displayName: "A", organizationName: nil, billingType: nil, addedAt: now)
        let b = AccountRecord(id: "org-2", displayName: "A", organizationName: nil, billingType: nil, addedAt: now)
        #expect(a != b)
    }

    @Test func identifiable_idIsOrgId() {
        let record = AccountRecord(id: "org-test", displayName: nil, organizationName: nil, billingType: nil, addedAt: Date())
        #expect(record.id == "org-test")
    }

    // MARK: - isPendingIdentity edge cases

    @Test func isPendingIdentity_falseForEmptyString() {
        let record = AccountRecord(id: "", displayName: nil, organizationName: nil, billingType: nil, addedAt: Date())
        #expect(!record.isPendingIdentity)
    }

    @Test func isPendingIdentity_falseForPendingWithoutDash() {
        let record = AccountRecord(id: "pending", displayName: nil, organizationName: nil, billingType: nil, addedAt: Date())
        #expect(!record.isPendingIdentity)
    }

    @Test func isPendingIdentity_trueForPendingDashEmpty() {
        // "pending-" with nothing after the dash is still a valid prefix match
        let record = AccountRecord(id: "pending-", displayName: nil, organizationName: nil, billingType: nil, addedAt: Date())
        #expect(record.isPendingIdentity)
    }

    @Test func isPendingIdentity_caseSensitive() {
        let record = AccountRecord(id: "Pending-ABC", displayName: nil, organizationName: nil, billingType: nil, addedAt: Date())
        #expect(!record.isPendingIdentity) // case-sensitive: "Pending" != "pending"
    }

    @Test func equatable_differentMetadataSameOtherwise() {
        let now = Date()
        let a = AccountRecord(id: "org-1", displayName: "Alice", organizationName: "Org A", billingType: "pro", addedAt: now)
        let b = AccountRecord(id: "org-1", displayName: "Bob", organizationName: "Org B", billingType: "teams", addedAt: now)
        // Synthesized Equatable compares ALL fields — different metadata means not equal
        #expect(a != b)
    }
}
