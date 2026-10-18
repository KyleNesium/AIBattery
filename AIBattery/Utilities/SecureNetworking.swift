import Foundation
import os

/// Centralized networking layer that enforces security defaults:
/// - Ephemeral URLSession (no disk cache, no cookies, no credentials persisted)
/// - Response size limit to prevent memory exhaustion from oversized payloads
enum SecureNetworking {
    /// Maximum response body size (2 MB). All legitimate API responses are well under this.
    static let maxResponseSize = 2_000_000

    /// Refuses every redirect. URLSession follows 3xx by default and re-issues the
    /// request — including its `Authorization: Bearer …` header — to whatever host the
    /// `Location` names. None of the endpoints this app talks to legitimately redirect,
    /// so the only thing following one could accomplish is replaying a token or an API
    /// key somewhere it was never meant to go.
    final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(
            _: URLSession,
            task _: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest _: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            AppLogger.network.warning("Refused a \(response.statusCode) redirect")
            completionHandler(nil)
        }
    }

    private static let redirectDelegate = NoRedirectDelegate()

    /// Shared ephemeral session — no disk cache, cookies, or credential storage, and
    /// no redirect following.
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config, delegate: redirectDelegate, delegateQueue: nil)
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

    /// Fetch data, aborting a response that exceeds `maxResponseSize` WHILE it streams.
    /// Buffering the whole body first and checking its size afterwards decided only
    /// whether to keep the bytes — the memory had already been spent, which is the one
    /// thing the cap exists to prevent.
    static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let (stream, response) = try await session.bytes(for: request)

        // Trust the advertised length when it is already over the cap: no point reading
        // a byte. A missing or lying header is caught by the accumulator below.
        if response.expectedContentLength > Int64(maxResponseSize) {
            AppLogger.network.warning("Response declared \(response.expectedContentLength) bytes, discarding")
            throw URLError(.dataLengthExceedsMaximum)
        }

        var data = Data()
        data.reserveCapacity(min(Int(max(response.expectedContentLength, 0)), maxResponseSize))
        for try await byte in stream {
            data.append(byte)
            if data.count > maxResponseSize {
                AppLogger.network.warning("Response exceeded \(maxResponseSize) bytes mid-stream, discarding")
                throw URLError(.dataLengthExceedsMaximum)
            }
        }
        return (data, response)
    }
}
