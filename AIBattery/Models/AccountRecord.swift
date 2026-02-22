import Foundation

/// Persistent identity for a Claude account (one OAuth org).
///
/// Stored as a JSON array in UserDefaults (`aibattery_accounts`).
/// The `id` starts as `"pending-<UUID>"` on initial auth and gets
/// resolved to the real `anthropic-organization-id` after the first
/// successful API call.
public struct AccountRecord: Codable, Identifiable, Equatable {
    /// Organization ID from the API, or `"pending-<UUID>"` before first fetch.
    public var id: String
    public var displayName: String?
    public var billingType: String?
    public var addedAt: Date

    /// Whether this account's identity hasn't been confirmed by the API yet.
    public var isPendingIdentity: Bool { id.hasPrefix("pending-") }
}
