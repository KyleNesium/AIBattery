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
    /// Which service this account belongs to. Decodes as `.claude` when absent
    /// so records persisted before v2.7 load unchanged (no migration).
    public var provider: AIProvider
    /// Codex only: ChatGPT OAuth (nil / `.chatgpt`) or an OpenAI API key (`.apiKey`).
    public var codexAccessMode: CodexAccessMode?
    /// Identity the provider told us, never typed by the user: the email claim of a
    /// Codex id_token, or the Claude workspace name from the profile headers. Shown
    /// only when `displayName` is empty, masked in the popover by default
    /// (`AccountStore.identityLabel`). Decodes as nil for records persisted before it existed.
    public var discoveredIdentity: String?

    /// Whether this account's identity hasn't been confirmed by the API yet.
    public var isPendingIdentity: Bool { id.hasPrefix("pending-") }

    /// Codex account authenticated with an OpenAI API key (pay-per-token, no windows).
    public var isAPIKeyAccount: Bool { provider == .codex && codexAccessMode == .apiKey }

    public init(
        id: String,
        displayName: String? = nil,
        billingType: String? = nil,
        addedAt: Date,
        provider: AIProvider = .claude,
        codexAccessMode: CodexAccessMode? = nil,
        discoveredIdentity: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.billingType = billingType
        self.addedAt = addedAt
        self.provider = provider
        self.codexAccessMode = codexAccessMode
        self.discoveredIdentity = discoveredIdentity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        billingType = try container.decodeIfPresent(String.self, forKey: .billingType)
        addedAt = try container.decode(Date.self, forKey: .addedAt)
        provider = try container.decodeIfPresent(AIProvider.self, forKey: .provider) ?? .claude
        codexAccessMode = try container.decodeIfPresent(CodexAccessMode.self, forKey: .codexAccessMode)
        discoveredIdentity = try container.decodeIfPresent(String.self, forKey: .discoveredIdentity)
    }
}
