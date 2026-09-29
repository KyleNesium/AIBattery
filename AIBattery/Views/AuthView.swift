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
    /// already knows which provider button the user clicked). Non-nil shows the
    /// Claude | Codex provider picker above the sign-in content.
    var onToggleProvider: (() -> Void)?
    @State private var authCode: String = ""
    @State private var isAwaitingSignIn = false
    @State private var isExchanging = false
    @State private var errorMessage: String?
    /// Whether `~/.codex/auth.json` holds an importable ChatGPT-mode login. Resolved
    /// once off the render path (`.task`) — a file read inside `body` re-ran on every
    /// evaluation (Plan 1 review F8).
    @State private var cliLoginAvailable = false
    /// Codex API-key entry (pay-per-token accounts).
    @State private var showAPIKeyField = false
    @State private var apiKeyInput = ""

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

            // Signed-out root only: both providers get equal billing. The add-account
            // overlay already knows which provider the user picked.
            if let onToggleProvider, !isAwaitingSignIn {
                let selection = Binding<AIProvider>(
                    get: { provider },
                    set: { newValue in
                        if newValue != provider {
                            onToggleProvider()
                        }
                    }
                )
                Picker("Provider", selection: selection) {
                    Text("\(AIProvider.claude.glyph) Claude").tag(AIProvider.claude)
                    Text("\(AIProvider.codex.glyph) Codex").tag(AIProvider.codex)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Provider to sign in with")
                .accessibilityHint("Choose between a Claude account and a Codex (OpenAI) account")
                .help("Choose which provider to sign in with")
            }

            if !isAddingAccount, let reason = oauthManager.lastSignOutReason {
                HStack(spacing: Spacing.inner) {
                    Image(systemName: "info.circle")
                        .font(Typography.tinyLabel)
                        .foregroundStyle(ThemeColors.caution)
                    Text(reason)
                        .font(Typography.tinyLabel)
                        .foregroundStyle(ThemeColors.caution)
                        .multilineTextAlignment(.leading)
                }
                .accessibilityElement(children: .combine)
            }

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
        if !isAwaitingSignIn {
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
                        isAwaitingSignIn = false
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
        if !isAwaitingSignIn {
            VStack(spacing: Spacing.section) {
                Text(isAddingAccount
                    ? "Connect another ChatGPT or OpenAI account to watch a second Codex quota."
                    : "Connect your ChatGPT or OpenAI account to see Codex usage, credits and rate limits.")
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

                if cliLoginAvailable {
                    LinkActionButton(
                        label: "Import Codex CLI login",
                        icon: "square.and.arrow.down",
                        help: "Seed a Codex account from your existing Codex CLI login (ChatGPT or API key)",
                        accessibilityLabel: "Import Codex CLI login",
                        accessibilityHint: "Seeds a Codex account without a browser round-trip",
                        action: importCodexCLILogin
                    )
                }

                if showAPIKeyField {
                    VStack(spacing: Spacing.inner) {
                        SecureField("sk-…", text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                            .font(Typography.monoCaption)
                            .onSubmit(submitAPIKey)
                            .accessibilityLabel("OpenAI API key")
                        HStack {
                            Text("Pay-per-token: shows per-minute API limits and real spend at API rates.")
                                .font(Typography.tinyLabel)
                                .foregroundStyle(ThemeColors.tertiaryLabel)
                            Spacer()
                            Button(action: submitAPIKey) {
                                if isExchanging {
                                    ProgressView().scaleEffect(0.6)
                                } else {
                                    Text("Connect")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(ThemeColors.action)
                            .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isExchanging)
                            .accessibilityLabel(isExchanging ? "Connecting" : "Connect API key")
                            .accessibilityHint("Validates the key and adds the account")
                        }
                        LinkActionButton(
                            label: "Use ChatGPT sign-in instead",
                            icon: "arrow.uturn.backward",
                            help: "Go back to the ChatGPT browser sign-in",
                            accessibilityLabel: "Use ChatGPT sign-in instead",
                            accessibilityHint: "Hides the API key field",
                            action: {
                                showAPIKeyField = false
                                apiKeyInput = ""
                                errorMessage = nil
                            }
                        )
                    }
                } else {
                    LinkActionButton(
                        label: "Use an OpenAI API key instead",
                        icon: "key",
                        help: "For Codex in API-key mode (pay-per-token) — no ChatGPT subscription",
                        accessibilityLabel: "Use an OpenAI API key",
                        accessibilityHint: "Shows a field to paste an OpenAI API key",
                        action: { showAPIKeyField = true }
                    )
                }
            }
            .task {
                let available = await Task.detached { CodexAuthFileImporter.cliLoginAvailable }.value
                cliLoginAvailable = available
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
                    isAwaitingSignIn = false
                    errorMessage = nil
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
        isAwaitingSignIn = true
    }

    private func startCodexAuth() {
        errorMessage = nil
        guard let url = oauthManager.startCodexAuthFlow() else {
            errorMessage = "Couldn't start sign-in (port 1455 busy — is a Codex CLI login running?)"
            return
        }
        isAwaitingSignIn = true
        // Start awaiting the callback BEFORE opening the browser. The local callback
        // server can receive the OAuth redirect before this Task's first `await` runs
        // if the browser round-trips fast (it's all localhost) — opening the browser
        // first risks the redirect arriving while nothing is awaiting it yet, which
        // drops the callback and hangs the waiting state. See Task 9 review.
        Task {
            let result = await oauthManager.completeCodexAuthFlow()
            isAwaitingSignIn = false
            if case .failure(let error) = result, !error.isCancellation {
                errorMessage = error.userMessage
            }
            // Success needs no handling here — the account lands in AccountStore
            // and UsagePopoverView's onChange dismisses the overlay.
        }
        NSWorkspace.shared.open(url)
    }

    private func submitAPIKey() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !isExchanging else { return }
        errorMessage = nil
        // Shape check before any network: an obvious typo fails instantly and offline.
        guard OAuthManager.looksLikeOpenAIAPIKey(key) else {
            errorMessage = OAuthManager.AuthError.malformedAPIKeyMessage
            return
        }
        isExchanging = true
        Task {
            // Free check first so a mistyped key fails here, not on the first paid probe.
            // A transient failure (.unknown) doesn't block — the account can still be added.
            let validation = await CodexRateLimitFetcher.shared.validateAPIKey(key)
            isExchanging = false
            if validation == .invalid {
                errorMessage = "OpenAI rejected this API key. Check it at platform.openai.com/api-keys."
                return
            }
            if case .failure(let error) = oauthManager.registerCodexAPIKey(key) {
                errorMessage = error.userMessage
            } else {
                apiKeyInput = ""
                if validation == .unknown {
                    // Not a failure — say so, since the first refresh will do the real check.
                    errorMessage = "Couldn't verify the key right now (offline?). Added anyway — it's checked on the first refresh."
                }
            }
            // Success auto-dismisses via AccountStore, like the OAuth flow.
        }
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
