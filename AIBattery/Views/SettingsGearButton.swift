import SwiftUI

/// The Settings gear, shared by the detail header (`PopoverHeaderView`) and the
/// overview header so both rows carry the identical control: same symbol, weight,
/// hover tone and hit target. An available update shows as `UpdateArrowButton` beside
/// the gear instead of a badge on it.
struct SettingsGearButton: View {
    @Binding var showSettings: Bool
    /// Spelled-out label beside the gear. The detail header has a title row to give the
    /// icon context; the overview's footer does not, so there it says "Settings".
    var label: String?
    @State private var hovered = false

    var body: some View {
        Button(action: { withAnimation(MotionConstants.standard) { showSettings.toggle() } }) {
            HStack(spacing: Spacing.inner) {
                Image(systemName: "gearshape")
                    .font(Typography.headerGear)
                    .iconHover(.turn, active: hovered)
                    .frame(
                        width: label == nil ? Layout.accountChipHeight : nil,
                        height: Layout.accountChipHeight
                    )
                if let label {
                    Text(label)
                        .font(Typography.caption)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(showSettings || hovered ? .primary : .secondary)
        .onHover { hovered = $0 }
        .help("Settings")
        .accessibilityLabel("Settings")
        .accessibilityHint(showSettings ? "Close settings" : "Open settings")
    }
}
