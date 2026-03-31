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
        VStack(spacing: Spacing.authGap) {
            // Header
            VStack(spacing: Spacing.inner) {
                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: Layout.iconClipRadius))
                }
                Text("AI Battery")
                    .font(Typography.sectionHeader)
                Text(isAddingAccount ? "Add another Claude account" : "Sign in with your Claude account")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
            }

            StyledDivider()

            if !isWaitingForCode {
                // Step 1: Start auth
                VStack(spacing: Spacing.section) {
                    Text(isAddingAccount
                        ? "Connect another Claude account to monitor multiple orgs from AI Battery."
                        : "Connect your Anthropic account to see your usage, rate limits, and plan details.")
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button(action: startAuth) {
                        HStack(spacing: Spacing.gap) {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                                .font(Typography.authIcon)
                            Text("Sign In")
                                .font(Typography.buttonLabel)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.gap)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .accessibilityLabel("Sign in with Claude")
                    .accessibilityHint("Opens browser to sign in with your Anthropic account")
                    .help("Opens browser to sign in with your Anthropic account")
                }
            } else {
                // Step 2: Paste code
                VStack(spacing: Spacing.section) {
                    HStack(spacing: Spacing.inner) {
                        Image(systemName: "1.circle.fill")
                            .foregroundStyle(ThemeColors.caution)
                            .font(Typography.caption)
                        Text("Sign in via the browser window that just opened")
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: Spacing.inner) {
                        Image(systemName: "2.circle.fill")
                            .foregroundStyle(ThemeColors.caution)
                            .font(Typography.caption)
                        Text("Copy the authorization code shown after signing in")
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: Spacing.inner) {
                        Image(systemName: "3.circle.fill")
                            .foregroundStyle(ThemeColors.caution)
                            .font(Typography.caption)
                        Text("Paste it below:")
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    TextField("Paste code...", text: $authCode)
                        .textFieldStyle(.roundedBorder)
                        .font(Typography.monoCaption)
                        .onSubmit(submitCode)
                        .accessibilityLabel("Authorization code")
                        .accessibilityHint("Paste the code from the browser")

                    HStack(spacing: Spacing.section) {
                        Button("Cancel") {
                            isWaitingForCode = false
                            authCode = ""
                            errorMessage = nil
                        }
                        .buttonStyle(.plain)
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Cancel authentication")
                        .help("Go back to sign-in")

                        Spacer()

                        Button(action: submitCode) {
                            if isExchanging {
                                ProgressView()
                                    .scaleEffect(0.6)
                            } else {
                                Text("Connect")
                                    .font(Typography.buttonLabel)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.accentColor)
                        .disabled(authCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isExchanging)
                        .accessibilityLabel(isExchanging ? "Connecting" : "Connect")
                        .accessibilityHint("Submit authorization code")
                        .help("Submit authorization code to complete sign-in")
                    }
                }
            }

            if let error = errorMessage {
                HStack(spacing: Spacing.inner) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(Typography.tinyLabel)
                        .foregroundStyle(ThemeColors.danger)
                    Text(error)
                        .font(Typography.tinyLabel)
                        .foregroundStyle(ThemeColors.danger)
                }
            }

            StyledDivider()

            // Footer
            HStack {
                if isAddingAccount, let onCancel {
                    Button("Cancel") { onCancel() }
                        .buttonStyle(.plain)
                        .font(Typography.tinyLabel)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Cancel adding account")
                } else {
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                        .buttonStyle(.plain)
                        .font(Typography.tinyLabel)
                        .foregroundStyle(.secondary)
                        .keyboardShortcut("q", modifiers: .command)
                }
                Spacer()
            }
        }
        .padding(Spacing.sectionHorizontal)
        .frame(width: Layout.popoverWidth)
        .contentShape(Rectangle())
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
