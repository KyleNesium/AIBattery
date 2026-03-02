import Foundation

/// Shared ephemeral URLSession and size-checked fetch helper.
///
/// All network services use this instead of `URLSession.shared` to ensure:
/// - **No disk cache**: ephemeral configuration prevents responses (including
///   OAuth token exchanges containing access/refresh tokens) from being written
///   to `~/Library/Caches/`.
/// - **Response size limit**: guards against a compromised or misbehaving endpoint
///   sending a multi-GB response that would cause OOM. Every expected response
///   from Anthropic, GitHub, and Statuspage is well under 100 KB.
enum SecureNetworking {
    /// Ephemeral session — no disk cache, no persistent cookies, no credential storage.
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        return URLSession(configuration: config)
    }()

    /// Maximum response body size (2 MB).
    static let maxResponseBytes = 2_000_000

    /// Fetch data with response size validation.
    /// Throws `URLError(.dataLengthExceedsMaximum)` if the response exceeds `maxResponseBytes`.
    static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let (data, response) = try await session.data(for: request)
        guard data.count <= maxResponseBytes else {
            throw URLError(.dataLengthExceedsMaximum)
        }
        return (data, response)
    }

    // MARK: - File Safety

    /// POSIX world-writable bit (others write permission).
    static let worldWritableBit: Int = 0o002

    /// Returns `true` if the file at `path` is world-writable.
    /// A world-writable file in `~/.claude/` could be tampered with by another
    /// user on a shared machine. Returns `false` if the file can't be stat'd
    /// (caller will hit a different error when trying to read).
    static func isWorldWritable(atPath path: String) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let posix = attrs[.posixPermissions] as? Int else {
            return false
        }
        return (posix & worldWritableBit) != 0
    }
}
