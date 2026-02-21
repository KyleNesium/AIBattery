import SwiftUI

/// Authentication view shown when the user is not authenticated.
/// Handles the OAuth PKCE flow: opens browser → user pastes code → tokens exchanged.
///
/// When `isAddingAccount` is true, shows different copy for the "add another account" flow
/// and displays a Cancel button to return to the main view.
public struct AuthView: View {
    @ObservedObject var oauthManager: OAuthManager
    var isAddingAccount: Bool = false
    var onCancel: (() -> Void)?
    @State private var authCode: String = ""
    @State private var isWaitingForCode = false
    @State private var isExchanging = false
    @State private var errorMessage: String?

    public init(oauthManager: OAuthManager, isAddingAccount: Bool = false, onCancel: (() -> Void)? = nil) {
        self.oauthManager = oauthManager
        self.isAddingAccount = isAddingAccount
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 12) {
            // Header
            VStack(spacing: 4) {
                Text("✦ AI Battery")
                    .font(.headline)
                Text(isAddingAccount ? "Add another Claude account" : "Sign in with your Claude account")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            if !isWaitingForCode {
                // Step 1: Start auth
                VStack(spacing: 8) {
                    Text(isAddingAccount
                        ? "Connect a second Claude account to monitor both from AI Battery."
                        : "Connect your Anthropic account to see your usage, rate limits, and plan details.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button(action: startAuth) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                                .font(.system(size: 13))
                            Text("Authenticate")
                                .font(.subheadline.weight(.medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .accessibilityLabel("Authenticate with Claude")
                    .accessibilityHint("Opens browser to sign in")
                }
            } else {
                // Step 2: Paste code
                VStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "1.circle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Text("Sign in via the browser window that just opened")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 4) {
                        Image(systemName: "2.circle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Text("Copy the authorization code shown after signing in")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 4) {
                        Image(systemName: "3.circle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Text("Paste it below:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    TextField("Paste authorization code...", text: $authCode)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                        .accessibilityLabel("Authorization code")
                        .accessibilityHint("Paste the code from the browser")

                    HStack(spacing: 8) {
                        Button("Cancel") {
                            isWaitingForCode = false
                            authCode = ""
                            errorMessage = nil
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Cancel authentication")

                        Spacer()

                        Button(action: submitCode) {
                            if isExchanging {
                                ProgressView()
                                    .scaleEffect(0.6)
                            } else {
                                Text("Connect")
                                    .font(.subheadline.weight(.medium))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.accentColor)
                        .disabled(authCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isExchanging)
                        .accessibilityLabel(isExchanging ? "Connecting" : "Connect")
                        .accessibilityHint("Submit authorization code")
                    }
                }
            }

            if let error = errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }

            Divider()

            // Footer
            HStack {
                if isAddingAccount, let onCancel {
                    Button("Cancel") { onCancel() }
                        .buttonStyle(.plain)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Cancel adding account")
                } else {
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                        .buttonStyle(.plain)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    private func startAuth() {
        errorMessage = nil
        guard let url = oauthManager.startAuthFlow(addingAccount: isAddingAccount) else {
            errorMessage = "Failed to create authorization URL"
            return
        }
        NSWorkspace.shared.open(url)
        isWaitingForCode = true
    }

    private func submitCode() {
        let code = authCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }

        isExchanging = true
        errorMessage = nil

        Task {
            let result = await oauthManager.exchangeCode(code)
            await MainActor.run {
                isExchanging = false
                switch result {
                case .success:
                    break // isAuthenticated triggers navigation via AIBatteryApp
                case .failure(let error):
                    errorMessage = error.userMessage
                    authCode = ""
                }
            }
        }
    }
}
