import Foundation
import os

/// Centralized networking layer that enforces security defaults:
/// - Ephemeral URLSession (no disk cache, no cookies, no credentials persisted)
/// - Response size limit to prevent memory exhaustion from oversized payloads
enum SecureNetworking {
    /// Maximum response body size (2 MB). All legitimate API responses are well under this.
    static let maxResponseSize = 2_000_000

    /// Shared ephemeral session — no disk cache, cookies, or credential storage.
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    /// True when a thrown transport error is the caller's own cancellation rather than
    /// the endpoint failing — a fan-out torn down by a toggle flip or an account change
    /// surfaces as `URLError(.cancelled)` / `CancellationError` / `Task.isCancelled`.
    /// Fetchers must not count these toward endpoint backoff or status failure counts.
    static func isCancellation(_ error: Error) -> Bool {
        if Task.isCancelled || error is CancellationError {
            return true
        }
        return (error as? URLError)?.code == .cancelled
    }

    /// Fetch data with size guard. Drops responses exceeding `maxResponseSize`.
    static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let (data, response) = try await session.data(for: request)
        if data.count > maxResponseSize {
            AppLogger.network.warning("Response too large (\(data.count) bytes), discarding")
            throw URLError(.dataLengthExceedsMaximum)
        }
        return (data, response)
    }
}
