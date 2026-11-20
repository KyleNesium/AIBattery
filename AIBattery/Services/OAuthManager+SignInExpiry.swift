import Foundation

/// What happens when a provider rejects an account's sign-in (its refresh token was revoked
/// or expired), and the room a new sign-in needs at the per-provider cap.
///
/// Until 3.6.0 a rejected sign-in removed the account. It vanished from the overview, its
/// "session expired" message never showed while another account was signed in, and the
/// next launch's prune dropped its history (seen 2026-11-18). Now the record stays and
/// shows as a sign-in card; signing in again merges back into it (`AccountStore.update`).
@MainActor
extension OAuthManager {
    /// The provider rejected this account's sign-in. Drops the credential and keeps the
    /// account (its name, identity and history), and moves the popover to a signed-in
    /// account when the rejected one was showing.
    func expireSignIn(accountId id: String) {
        guard let account = accountStore.account(id: id) else { return }
        clearSignIn(id, reason: Self.sessionExpiredReason(for: account.provider))
        let label = AccountStore.identityLabel(
            for: account,
            providerIndex: AccountStore.providerIndex(of: account, in: accountStore.accounts),
            maskEmail: true
        )
        NotificationManager.shared.notifySignInExpired(accountLabel: label)
        moveOffSignedOutActiveAccount()
        updateAuthState()
    }

    /// The active account drives the whole popover, so a signed-out one put everything on
    /// the sign-in screen while other accounts still worked. Moves to the first signed-in
    /// account; with none, stays, and the sign-in screen is then the right thing to show.
    func moveOffSignedOutActiveAccount() {
        guard let activeId = accountStore.activeAccountId, !isAuthenticated(accountId: activeId),
              let signedIn = AccountStore.displayOrdered(accountStore.accounts)
                  .first(where: { isAuthenticated(accountId: $0.id) })
        else { return }
        accountStore.setActive(id: signedIn.id)
    }

    /// Whether a new sign-in to `provider` fits: under the cap, or there is a signed-out
    /// account it can replace.
    func hasRoomForSignIn(provider: AIProvider) -> Bool {
        accountStore.canAddAccount(provider: provider) || signedOutAccount(of: provider) != nil
    }

    /// At the cap, removes one signed-out account of `provider` so a new sign-in fits.
    /// Call it only once the new sign-in holds its tokens: removing earlier would lose the
    /// record to a sign-in that is then cancelled. Returns whether there is room.
    @discardableResult
    func makeRoomForSignIn(provider: AIProvider) -> Bool {
        if accountStore.canAddAccount(provider: provider) {
            return true
        }
        guard let replaced = signedOutAccount(of: provider) else { return false }
        AppLogger.oauth.info("Replacing signed-out account \(replaced.id, privacy: .public) at the \(provider.rawValue, privacy: .public) account cap")
        accountStore.remove(id: replaced.id)
        return true
    }

    private func signedOutAccount(of provider: AIProvider) -> AccountRecord? {
        accountStore.accounts.first {
            $0.provider == provider && !$0.isPendingIdentity && !isAuthenticated(accountId: $0.id)
        }
    }
}
