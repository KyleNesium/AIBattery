import SwiftUI
import AppKit

/// Adds click-to-copy behavior with hover highlight and clipboard icon feedback.
struct CopyableModifier: ViewModifier {
    let value: String
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
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation(MotionConstants.standard) {
                        copied = false
                    }
                }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Copy \(value) to clipboard")
    }
}

/// Lightweight click-to-copy for dense areas (e.g. token tags).
/// Skips cursor push/pop, help tooltip, and per-element overlay to reduce modifier stack overhead.
struct LightCopyableModifier: ViewModifier {
    let value: String
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Spacing.xsmall)
            .padding(.vertical, Spacing.micro)
            .background(
                RoundedRectangle(cornerRadius: Spacing.xsmall)
                    .fill(isHovered ? ThemeColors.copyableHoverFill : Color.clear)
            )
            .onHover { isHovered = $0 }
            .onTapGesture {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Copy \(value)")
    }
}

extension View {
    /// Makes this view tappable to copy the given value to the clipboard.
    func copyable(_ value: String) -> some View {
        modifier(CopyableModifier(value: value))
    }

    /// Lightweight copy — fewer @State variables, no cursor change or overlay feedback.
    /// Use in dense areas (token tags, per-model breakdowns) where many elements share the same row.
    func lightCopyable(_ value: String) -> some View {
        modifier(LightCopyableModifier(value: value))
    }
}
