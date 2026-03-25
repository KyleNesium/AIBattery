import SwiftUI

// MARK: - Error

struct PopoverErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title3)
                .foregroundStyle(ThemeColors.caution)
            Text(message)
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            Button(action: onRetry) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(Typography.monoTiny)
                    Text("Retry")
                        .font(Typography.caption)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(ThemeColors.action)
            .accessibilityHint("Retry loading usage data")
        }
        .padding(.horizontal, Spacing.sectionHorizontal)
        .frame(maxWidth: .infinity)
        .frame(height: 100)
    }
}

// MARK: - Empty

struct PopoverEmptyView: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("No Claude Code data found")
                .font(Typography.caption)
                .foregroundStyle(.secondary)
            Text("Start a Claude Code session to populate usage data.\nData appears automatically once Claude Code is running.")
                .font(Typography.tinyLabel)
                .foregroundStyle(ThemeColors.tertiaryLabel)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Spacing.sectionHorizontal)
        .frame(maxWidth: .infinity)
        .frame(height: 80)
    }
}

// MARK: - Idle Filtered

struct PopoverIdleFilteredView: View {
    let idleSessionMinutes: Double

    var body: some View {
        VStack(spacing: 4) {
            Text("No active sessions")
                .font(Typography.caption)
                .foregroundStyle(.secondary)
            let idleMinutes = Int(idleSessionMinutes)
            if idleMinutes > 0 {
                Text("Idle cutoff: \(idleMinutes)m")
                    .font(Typography.tinyLabel)
                    .foregroundStyle(ThemeColors.tertiaryLabel)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sectionHorizontal * 0.75)
    }
}
