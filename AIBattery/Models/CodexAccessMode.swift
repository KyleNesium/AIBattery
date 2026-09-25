import Foundation

/// How a Codex account authenticates. nil on persisted records means ChatGPT OAuth.
public enum CodexAccessMode: String, Codable, Sendable {
    case chatgpt
    case apiKey
}
