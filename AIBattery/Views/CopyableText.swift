import SwiftUI
import AppKit

/// Adds click-to-copy behavior with hover highlight and clipboard icon feedback.
struct CopyableModifier: ViewModifier {
    let value: String
    @State private var copied = false
    @State private var isHovered = false
    /// Tracks the active feedback task so rapid taps restart the timer.
    @State private var feedbackTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
            )
            .overlay(alignment: .trailing) {
                if copied {
                    Image(systemName: "doc.on.clipboard.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .transition(.scale.combined(with: .opacity))
                        .padding(.trailing, -13)
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
            .help("Click to copy: \(value)")
            .onTapGesture {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)

                // Cancel any previous feedback timer
                feedbackTask?.cancel()

                withAnimation(.easeOut(duration: 0.12)) {
                    copied = true
                }
                feedbackTask = Task {
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeIn(duration: 0.2)) {
                        copied = false
                    }
                }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Copy \(value) to clipboard")
    }
}

extension View {
    /// Makes this view tappable to copy the given value to the clipboard.
    func copyable(_ value: String) -> some View {
        modifier(CopyableModifier(value: value))
    }
}
