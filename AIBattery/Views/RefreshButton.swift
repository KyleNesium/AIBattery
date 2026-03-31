import SwiftUI

/// Refresh button with brief spin animation on tap.
struct RefreshButton: View {
    let action: () -> Void
    @State private var rotation: Double = 0
    @State private var isHovered = false

    var body: some View {
        Button {
            // Reset without animation first, then animate one full turn.
            // This avoids unbounded accumulation while always spinning forward.
            withAnimation(.none) { rotation = 0 }
            withAnimation(MotionConstants.spin) {
                rotation = 360
            }
            action()
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(Typography.tinyLabel)
                .rotationEffect(.degrees(rotation))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovered ? .primary : .secondary)
        .onHover { isHovered = $0 }
        .help("Refresh for latest session (R)")
        .accessibilityLabel("Refresh")
    }
}
