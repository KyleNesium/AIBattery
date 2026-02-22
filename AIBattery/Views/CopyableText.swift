import SwiftUI
import AppKit

/// Adds click-to-copy behavior with hover highlight and brief green checkmark feedback.
struct CopyableModifier: ViewModifier {
    let value: String
    @State private var showCheck = false
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
            )
            .overlay(alignment: .trailing) {
                if showCheck {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                        .transition(.opacity)
                        .padding(.trailing, -12)
                }
            }
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .help(value)
            .onTapGesture {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
                withAnimation(.easeInOut(duration: 0.15)) {
                    showCheck = true
                }
                Task {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
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
