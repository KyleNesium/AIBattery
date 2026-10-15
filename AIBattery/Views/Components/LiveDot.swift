import SwiftUI

/// A small dot that breathes while an account's provider is being used right now —
/// the one thing a list of accounts can't otherwise tell you: which of them your CLI
/// is hitting at this moment. It exists only while that is true; the rest of the time
/// there is nothing to see, which is the rule the whole overview follows.
///
/// Respects Reduce Motion: the dot stays, the breathing stops.
struct LiveDot: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: Layout.dotSizeSmall, height: Layout.dotSizeSmall)
            .opacity(breathing && !reduceMotion ? ThemeColors.liveDotDimOpacity : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(MotionConstants.breathe) { breathing = true }
            }
            .accessibilityLabel("Active now")
            .help("This provider is being used right now (activity in the last few minutes)")
    }
}
