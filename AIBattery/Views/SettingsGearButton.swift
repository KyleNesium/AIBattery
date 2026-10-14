import SwiftUI

/// The Settings gear, shared by the detail header (`PopoverHeaderView`) and the
/// overview header so both rows carry the identical control: same symbol, weight,
/// hover tone and hit target, and the same update badge when an available update's
/// banner was dismissed.
struct SettingsGearButton: View {
    @Binding var showSettings: Bool
    /// Badge the gear because an update was found and its banner dismissed.
    var showsUpdateBadge: Bool = false
    @State private var hovered = false

    var body: some View {
        Button(action: { withAnimation(MotionConstants.standard) { showSettings.toggle() } }) {
            Image(systemName: "gearshape")
                .font(Typography.headerGear)
                .frame(width: Layout.accountChipHeight, height: Layout.accountChipHeight)
                .overlay(alignment: .topTrailing) {
                    if showsUpdateBadge {
                        // A symbol, not a bare colored dot: readable without color vision.
                        Image(systemName: "arrow.up.circle.fill")
                            .font(Typography.decorativeIcon)
                            .foregroundStyle(ThemeColors.updateAvailable)
                            .padding(Spacing.tight)
                    }
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(showSettings || hovered ? .primary : .secondary)
        .onHover { hovered = $0 }
        .help(showsUpdateBadge ? "Settings — update available" : "Settings")
        .accessibilityLabel(showsUpdateBadge ? "Settings, update available" : "Settings")
        .accessibilityHint(showSettings ? "Close settings" : "Open settings")
    }
}
