import SwiftUI

/// Authentication view shown when the user is not authenticated.
///
/// Claude branch: opens browser → user pastes code → tokens exchanged (OAuth PKCE).
/// Codex branch: opens browser → local callback server receives the redirect →
/// tokens exchanged automatically (no code to paste).
///
/// When `isAddingAccount` is true, shows different copy for the "add another account" flow
/// and displays a Cancel button to return to the main view.
public struct AuthView: View {
    @ObservedObject var oauthManager: OAuthManager
    var provider: AIProvider = .claude
    var isAddingAccount: Bool = false
    var onCancel: (() -> Void)?
    /// Only set for the signed-out root (never for the add-account overlay, which
    /// already knows which provider button the user clicked). Non-nil enables the
    /// small "Sign in with X instead" footnote link in the footer.
    var onToggleProvider: (() -> Void)?
    @State private var authCode: String = ""
    @State private var isWaitingForCode = false
    @State private var isExchanging = false
    @State private var errorMessage: String?

    public init(
        oauthManager: OAuthManager,
        provider: AIProvider = .claude,
        isAddingAccount: Bool = false,
        onCancel: (() -> Void)? = nil,
        onToggleProvider: (() -> Void)? = nil
    ) {
        self.oauthManager = oauthManager
        self.provider = provider
        self.isAddingAccount = isAddingAccount
        self.onCancel = onCancel
        self.onToggleProvider = onToggleProvider
    }

    public var body: some View {
        VStack(spacing: Spacing.authGap) {
            // Header
            VStack(spacing: Spacing.inner) {
                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: Layout.appIconSize, height: Layout.appIconSize)
                        .clipShape(RoundedRectangle(cornerRadius: Layout.iconClipRadius))
                        .accessibilityHidden(true)
                }
                Text("AI Battery")
                    .font(Typography.sectionHeader)
                Text(headerSubtitle)
                    .font(Typography.caption)
                    .foregroundStyle(ThemeColors.secondaryLabel)
            }

            StyledDivider()

            if provider == .codex {
                codexContent
            } else {
                claudeContent
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
                        .foregroundStyle(ThemeColors.secondaryLabel)
                        .accessibilityLabel("Cancel adding account")
                        .accessibilityHint("Returns to the main popover")
                } else {
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                        .buttonStyle(.plain)
                        .font(Typography.tinyLabel)
                        .foregroundStyle(ThemeColors.secondaryLabel)
                        .keyboardShortcut("q", modifiers: .command)
                    if let onToggleProvider {
                        Spacer()
                        Button(action: onToggleProvider) {
                            Text(provider == .claude ? "Sign in with Codex instead" : "Sign in with Claude instead")
                        }
                        .buttonStyle(.plain)
                        .font(Typography.tinyLabel)
                        .foregroundStyle(ThemeColors.secondaryLabel)
                        .accessibilityLabel(provider == .claude ? "Sign in with Codex instead" : "Sign in with Claude instead")
                        .accessibilityHint("Switches the sign-in flow to the other provider")
                    }
                }
                Spacer()
            }
        }
        .padding(Spacing.sectionHorizontal)
        .frame(width: Layout.popoverWidth)
        .contentShape(Rectangle())
    }

    private var headerSubtitle: String {
        switch provider {
        case .claude:
            isAddingAccount ? "Add another Claude account" : "Sign in with your Claude account"
        case .codex:
            isAddingAccount ? "Add a Codex account" : "Sign in with your Codex (ChatGPT) account"
        }
    }

    // MARK: - Claude flow (paste-code)

    @ViewBuilder
    private var claudeContent: some View {
        if !isWaitingForCode {
            // Step 1: Start auth
            VStack(spacing: Spacing.section) {
                Text(isAddingAccount
                    ? "Connect another Claude account to monitor multiple orgs from AI Battery."
                    : "Connect your Anthropic account to see your usage, rate limits, and plan details.")
                    .font(Typography.caption)
                    .foregroundStyle(ThemeColors.secondaryLabel)
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
                .tint(ThemeColors.action)
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
                        .foregroundStyle(ThemeColors.secondaryLabel)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: Spacing.inner) {
                    Image(systemName: "2.circle.fill")
                        .foregroundStyle(ThemeColors.caution)
                        .font(Typography.caption)
                    Text("Copy the authorization code shown after signing in")
                        .font(Typography.caption)
                        .foregroundStyle(ThemeColors.secondaryLabel)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: Spacing.inner) {
                    Image(systemName: "3.circle.fill")
                        .foregroundStyle(ThemeColors.caution)
                        .font(Typography.caption)
                    Text("Paste it below:")
                        .font(Typography.caption)
                        .foregroundStyle(ThemeColors.secondaryLabel)
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
                    .foregroundStyle(ThemeColors.secondaryLabel)
                    .accessibilityLabel("Cancel authentication")
                    .accessibilityHint("Returns to the sign-in screen")
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
                    .tint(ThemeColors.action)
                    .disabled(authCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isExchanging)
                    .accessibilityLabel(isExchanging ? "Connecting" : "Connect")
                    .accessibilityHint("Submit authorization code")
                    .help("Submit authorization code to complete sign-in")
                }
            }
        }
    }

    // MARK: - Codex flow (browser round-trip, no code to paste)

    @ViewBuilder
    private var codexContent: some View {
        if !isWaitingForCode {
            VStack(spacing: Spacing.section) {
                Text("Connect your OpenAI account to see Codex usage and rate limits.")
                    .font(Typography.caption)
                    .foregroundStyle(ThemeColors.secondaryLabel)
                    .multilineTextAlignment(.center)

                Button(action: startCodexAuth) {
                    HStack(spacing: Spacing.gap) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(Typography.authIcon)
                        Text("Sign In with ChatGPT")
                            .font(Typography.buttonLabel)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.gap)
                }
                .buttonStyle(.borderedProminent)
                .tint(ThemeColors.action)
                .accessibilityLabel("Sign in with ChatGPT")
                .accessibilityHint("Opens browser to sign in with your OpenAI account")
                .help("Opens browser to sign in with your OpenAI account")

                if CodexAuthFileImporter.cliLoginAvailable {
                    LinkActionButton(
                        label: "Import Codex CLI login",
                        icon: "square.and.arrow.down",
                        help: "Seed a Codex account from your existing Codex CLI login",
                        accessibilityLabel: "Import Codex CLI login",
                        accessibilityHint: "Seeds a Codex account without a browser round-trip",
                        action: importCodexCLILogin
                    )
                }
            }
        } else {
            // Waiting for the local callback server to receive the OAuth redirect.
            VStack(spacing: Spacing.section) {
                HStack(spacing: Spacing.inner) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Complete the sign-in in your browser…")
                        .font(Typography.caption)
                        .foregroundStyle(ThemeColors.secondaryLabel)
                }

                Button("Cancel") {
                    oauthManager.cancelCodexAuthFlow()
                    isWaitingForCode = false
                }
                .buttonStyle(.plain)
                .font(Typography.caption)
                .foregroundStyle(ThemeColors.secondaryLabel)
                .accessibilityLabel("Cancel Codex sign-in")
                .accessibilityHint("Stops waiting for the browser sign-in and releases the local callback port")
                .help("Cancel sign-in")
            }
        }
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

    private func startCodexAuth() {
        errorMessage = nil
        guard let url = oauthManager.startCodexAuthFlow() else {
            errorMessage = "Couldn't start sign-in (port 1455 busy — is a Codex CLI login running?)"
            return
        }
        isWaitingForCode = true
        // Start awaiting the callback BEFORE opening the browser. The local callback
        // server can receive the OAuth redirect before this Task's first `await` runs
        // if the browser round-trips fast (it's all localhost) — opening the browser
        // first risks the redirect arriving while nothing is awaiting it yet, which
        // drops the callback and hangs the waiting state. See Task 9 review.
        Task {
            let result = await oauthManager.completeCodexAuthFlow()
            isWaitingForCode = false
            if case .failure(let error) = result {
                errorMessage = error.userMessage
            }
            // Success needs no handling here — the account lands in AccountStore
            // and UsagePopoverView's onChange dismisses the overlay.
        }
        NSWorkspace.shared.open(url)
    }

    private func importCodexCLILogin() {
        errorMessage = nil
        let result = CodexAuthFileImporter.importCurrentLogin(into: oauthManager)
        if case .failure(let error) = result {
            errorMessage = error.userMessage
        }
        // Success needs no further handling — same auto-dismiss path as the OAuth flow.
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
