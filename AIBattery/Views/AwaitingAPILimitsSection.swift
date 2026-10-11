import SwiftUI

/// Placeholder for an API-key Codex account before its first per-minute limit probe lands.
///
/// `CodexDisplayKind.apiLimits` is chosen from the account type alone, so the "API Limits"
/// tab is selected and highlighted from the moment the key is added — but `standardLimits`
/// stays nil until the first `/v1/responses` probe returns `x-ratelimit-*` headers, and the
/// `.sevenDay` slot renders `EmptyView` for this kind. Without this the user saw a
/// highlighted tab over blank space with nothing to explain it.
struct AwaitingAPILimitsSection: View {
    var body: some View {
        HStack(spacing: Spacing.inner) {
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: Layout.spinnerSize, height: Layout.spinnerSize)
                .accessibilityHidden(true)
            Text("Waiting for the first API-limit probe…")
                .font(Typography.caption)
                .foregroundStyle(ThemeColors.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.gap)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Waiting for the first API limit probe")
    }
}
