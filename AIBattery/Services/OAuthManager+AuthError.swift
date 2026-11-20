import Foundation

/// Why a sign-in or a token refresh failed, with the copy the user sees. Split out of
/// `OAuthManager.swift` to keep that file under the 800-line ceiling in CLAUDE.md.
@MainActor
extension OAuthManager {
    /// Auth error types for specific failure feedback.
    enum AuthError: Error {
        case noVerifier
        case invalidCode
        case expired
        case networkError
        /// Transient failure from the provider's token endpoint (5xx, 429, …). The
        /// provider picks the wording — a Codex sign-in must never blame Anthropic.
        case serverError(Int, provider: AIProvider = .claude)
        case maxAccountsReached
        /// OpenAI's token endpoint refused the Codex sign-in (400/401/403). Non-transient.
        case codexSignInRejected(Int)
        /// The user cancelled the Codex browser sign-in. Not an error to display.
        case cancelled
        case unknownError(String)

        var userMessage: String {
            switch self {
            case .noVerifier: "Auth flow not started. Please click Authenticate first."
            case .invalidCode: "Invalid authorization code. Please try again."
            case .expired: "Authorization code expired. Please re-authenticate."
            case .networkError: "Network error. Check your connection and try again."
            case .serverError(let code, .claude): "Anthropic's server returned \(code). This is a temporary issue on their end — please try again in a moment."
            case .serverError(let code, .codex): "OpenAI's sign-in server returned \(code). This is a temporary issue on their end — please try again in a moment."
            case .maxAccountsReached: "Maximum of \(AccountStore.maxAccountsPerProvider) accounts per provider reached. Remove one before adding another."
            case .codexSignInRejected(let code): "OpenAI rejected the sign-in (HTTP \(code)). Please try again."
            case .cancelled: ""
            case .unknownError(let msg): msg
            }
        }

        /// Whether this error is transient and the caller should preserve auth state.
        var isTransient: Bool {
            switch self {
            case .networkError, .serverError: true
            default: false
            }
        }

        nonisolated static let malformedAPIKeyMessage = "That doesn't look like an OpenAI API key (expected sk-…)."

        /// True when the user backed out on purpose — callers show no error copy.
        var isCancellation: Bool {
            if case .cancelled = self {
                return true
            }
            return false
        }

        /// Copy for a Codex browser sign-in that ended without a usable redirect.
        nonisolated static func codexCallbackFailure(_ error: CodexCallbackError) -> AuthError {
            switch error {
            case .providerError("cancelled"):
                .cancelled
            case .providerError("timeout"):
                .unknownError("Sign-in timed out after 3 minutes. Please try again.")
            case .providerError(let reason):
                .unknownError("OpenAI declined the sign-in (\(Self.sanitizedProviderReason(reason))). Please try again.")
            case .missingCode, .missingState, .notCallbackPath:
                .unknownError("The browser redirect was malformed. Please try again.")
            }
        }

        /// The `error` query parameter arrives on an open loopback port, so any local
        /// process can put arbitrary text in front of the user attributed to OpenAI.
        /// Keep recognisable OAuth codes, replace anything else with a generic word.
        nonisolated static func sanitizedProviderReason(_ reason: String) -> String {
            let known: Set = [
                "access_denied", "invalid_request", "invalid_scope", "invalid_client",
                "unauthorized_client", "unsupported_response_type", "server_error",
                "temporarily_unavailable", "interaction_required", "login_required",
                "consent_required", "account_selection_required",
            ]
            return known.contains(reason) ? reason : "unrecognised error"
        }
    }
}
