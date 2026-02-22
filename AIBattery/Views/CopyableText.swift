import SwiftUI
import AppKit

/// Adds click-to-copy behavior with brief green checkmark feedback.
struct CopyableModifier: ViewModifier {
    let value: String
    @State private var showCheck = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .trailing) {
                if showCheck {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }
            }
            .help(value)
            .onTapGesture {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
                withAnimation(.easeInOut(duration: 0.15)) {
                    showCheck = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showCheck = false
                    }
                }
            }
    }
}

extension View {
    /// Makes this view tappable to copy the given value to the clipboard.
    func copyable(_ value: String) -> some View {
        modifier(CopyableModifier(value: value))
    }
}
