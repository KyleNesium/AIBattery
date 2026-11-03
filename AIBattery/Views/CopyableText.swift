import SwiftUI
import AppKit

/// Adds click-to-copy behavior with hover highlight and clipboard icon feedback.
struct CopyableModifier: ViewModifier {
    let value: String
    /// Outer edges where the hover highlight bleeds past the text instead of insetting
    /// it. An edge-aligned value ("96% remaining", "Resets in 3h") otherwise sat 3pt
    /// inside the bar it labels, and 3pt off the non-copyable states that take its slot
    /// ("Throttled", "Limit reached"). Inner edges keep the inset so neighbours keep
    /// their spacing.
    var bleed: Edge.Set = []
    @State private var copied = false
    @State private var isHovered = false
    /// Whether we have an active cursor push on the stack.
    @State private var cursorPushed = false
    /// Tracks the active feedback task so rapid taps restart the timer.
    @State private var feedbackTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Spacing.xsmall)
            .padding(.vertical, Spacing.micro)
            .background(
                RoundedRectangle(cornerRadius: Spacing.xsmall)
                    .fill(isHovered ? ThemeColors.copyableHoverFill : Color.clear)
            )
            .overlay(alignment: .trailing) {
                if copied {
                    Image(systemName: "doc.on.clipboard.fill")
                        .font(Typography.clipboardIcon)
                        .foregroundStyle(ThemeColors.secondaryLabel)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityHidden(true)
                        .padding(.trailing, -Layout.clipboardIconOffset)
                }
            }
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    if !cursorPushed {
                        NSCursor.pointingHand.push()
                        cursorPushed = true
                    }
                } else {
                    if cursorPushed {
                        NSCursor.pop()
                        cursorPushed = false
                    }
                }
            }
            .onDisappear {
                feedbackTask?.cancel()
                if cursorPushed {
                    NSCursor.pop()
                    cursorPushed = false
                }
            }
            .help("Click to copy: \(value)")
            .onTapGesture {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
                NSAccessibility.post(element: NSApp as Any, notification: .valueChanged)

                // Cancel any previous feedback timer
                feedbackTask?.cancel()

                withAnimation(MotionConstants.standard) {
                    copied = true
                }
                feedbackTask = Task {
                    try? await Task.sleep(nanoseconds: MotionConstants.clipboardFeedbackNs)
                    guard !Task.isCancelled else { return }
                    withAnimation(MotionConstants.standard) {
                        copied = false
                    }
                }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Copy \(value) to clipboard")
            // Last, so drawing and hit-testing keep the padded area and only layout loses it.
            .padding(bleed, -Spacing.xsmall)
    }
}

extension View {
    /// Makes this view tappable to copy the given value to the clipboard. `bleed`: the
    /// row's outer edges this view sits on (see `CopyableModifier.bleed`).
    func copyable(_ value: String, bleed: Edge.Set = []) -> some View {
        modifier(CopyableModifier(value: value, bleed: bleed))
    }
}
