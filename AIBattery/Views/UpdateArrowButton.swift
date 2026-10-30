import SwiftUI

/// The one sign that a newer release exists: an arrow beside the gear that breathes in
/// the update colour. It appears only while `UsageViewModel.availableUpdate` is set and
/// replaces both the old header banner and the gear badge. Its visibility comes from
/// GitHub Releases while the click runs a Sparkle check against the appcast, so the two
/// can disagree for a few minutes after a release — the context menu keeps the release
/// page one click away for that case.
///
/// Respects Reduce Motion: the glow stays, the breathing stops (same rule as `LiveDot`).
struct UpdateArrowButton: View {
    let update: VersionChecker.UpdateInfo
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false
    @State private var hovered = false

    nonisolated static let releaseNotesTitle = "Release notes"
    nonisolated static let checkForUpdatesTitle = "Check for Updates"

    nonisolated static func helpText(version: String) -> String {
        "v\(version) available — click to update"
    }

    nonisolated static func accessibilityLabel(version: String) -> String {
        "Update available, version \(version)"
    }

    /// `nil` means "don't animate" — the only honest value under Reduce Motion.
    nonisolated static func breatheAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : MotionConstants.breathe
    }

    var body: some View {
        Button(action: { AboutSection.installUpdate(update) }) {
            Image(systemName: "arrow.up.circle")
                .font(Typography.headerGear)
                .foregroundStyle(ThemeColors.updateAvailable)
                .shadow(color: ThemeColors.updateAvailable.opacity(ThemeColors.chevronGlowOpacity), radius: Layout.glowRadius)
                // Inside the breathing opacity: the hover spring moves the glyph and
                // its glow together and leaves the repeating breath alone.
                .iconHover(.rise, active: hovered)
                .opacity(breathing ? ThemeColors.liveDotDimOpacity : 1)
                .frame(width: Layout.accountChipHeight, height: Layout.accountChipHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .onAppear {
            guard let animation = Self.breatheAnimation(reduceMotion: reduceMotion) else { return }
            withAnimation(animation) { breathing = true }
        }
        .contextMenu {
            Button(Self.releaseNotesTitle) {
                if let url = URL(string: update.url) {
                    NSWorkspace.shared.open(url)
                }
            }
            Button(Self.checkForUpdatesTitle) {
                AboutSection.installUpdate(update)
            }
        }
        .help(Self.helpText(version: update.version))
        .accessibilityLabel(Self.accessibilityLabel(version: update.version))
        .accessibilityHint("Downloads and installs the update; right-click for release notes")
    }
}
