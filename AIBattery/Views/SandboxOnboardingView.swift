#if APP_SANDBOX
import SwiftUI

/// Shown when the app lacks a security-scoped bookmark for `~/.claude/`.
/// Prompts the user to grant folder access via NSOpenPanel.
struct SandboxOnboardingView: View {
    var onAccessGranted: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Folder Access Required")
                .font(.headline)

            Text("AI Battery needs access to your **~/.claude** folder to read Claude Code usage data.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Button("Grant Access") {
                if SandboxAccessManager.shared.requestAccess() != nil,
                   SandboxAccessManager.shared.startAccessing() {
                    onAccessGranted()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .frame(width: 275)
        .padding()
    }
}
#endif
