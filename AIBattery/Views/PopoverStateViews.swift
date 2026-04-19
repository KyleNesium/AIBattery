import SwiftUI

// MARK: - Error

struct PopoverErrorView: View {
    let message: String
    let onRetry: () -> Void
    @State private var retryHovered = false

    var body: some View {
        VStack(spacing: Spacing.section) {
            Image(systemName: "exclamationmark.triangle")
                .font(Typography.stateIcon)
                .foregroundStyle(ThemeColors.caution)
            Text(message)
                .font(Typography.caption)
                .foregroundStyle(ThemeColors.secondaryLabel)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            Button(action: onRetry) {
                HStack(spacing: Spacing.inner) {
                    Image(systemName: "arrow.clockwise")
                        .font(Typography.monoTiny)
                    Text("Retry")
                        .font(Typography.caption)
                        .underline(retryHovered)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(ThemeColors.action)
            .onHover { retryHovered = $0 }
            .accessibilityHint("Retry loading usage data")
            .help("Retry loading usage data")
        }
        .padding(.horizontal, Spacing.sectionHorizontal)
        .frame(maxWidth: .infinity)
        .frame(height: Layout.stateHeightError)
    }
}

// MARK: - Empty

struct PopoverEmptyView: View {
    var body: some View {
        VStack(spacing: Spacing.inner) {
            Image(systemName: "tray")
                .font(Typography.stateIcon)
                .foregroundStyle(ThemeColors.tertiaryLabel)
            Text("No Claude Code data found")
                .font(Typography.caption)
                .foregroundStyle(ThemeColors.secondaryLabel)
            Text("Start a Claude Code session to populate usage data.\nData appears automatically once Claude Code is running.")
                .font(Typography.tinyLabel)
                .foregroundStyle(ThemeColors.tertiaryLabel)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Spacing.sectionHorizontal)
        .frame(maxWidth: .infinity)
        .frame(height: Layout.stateHeightEmpty)
    }
}

// MARK: - Idle Filtered

struct PopoverIdleFilteredView: View {
    let idleSessionMinutes: Double

    var body: some View {
        VStack(spacing: Spacing.inner) {
            Image(systemName: "moon.zzz")
                .font(Typography.stateIcon)
                .foregroundStyle(ThemeColors.tertiaryLabel)
            Text("No active sessions")
                .font(Typography.caption)
                .foregroundStyle(ThemeColors.secondaryLabel)
            let idleMinutes = Int(idleSessionMinutes)
            if idleMinutes > 0 {
                Text("Idle cutoff: \(idleMinutes)m")
                    .font(Typography.tinyLabel)
                    .foregroundStyle(ThemeColors.tertiaryLabel)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.authGap)
    }
}
