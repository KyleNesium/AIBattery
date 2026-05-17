import SwiftUI

/// A news-ticker style text view that scrolls horizontally when text is wider than the container.
/// Supports multiple texts — cycles through them with fade transitions, scrolling each if needed.
/// Single text bounces back and forth; if the text fits, it displays statically.
struct MarqueeText: View {
    let texts: [String]
    var font: Font = Typography.tinyLabel
    var color: Color = ThemeColors.secondaryLabel

    @State private var currentIndex: Int = 0
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var animating = false
    @State private var textOpacity: Double = 1.0
    @State private var pendingWork: DispatchWorkItem?

    private var currentText: String {
        texts.isEmpty ? "" : texts[currentIndex % texts.count]
    }

    private var needsScroll: Bool { textWidth > containerWidth && containerWidth > 0 }
    private var hasMultiple: Bool { texts.count > 1 }

    /// Convenience init for a single text string.
    init(text: String, font: Font = Typography.tinyLabel, color: Color = ThemeColors.secondaryLabel) {
        self.texts = [text]
        self.font = font
        self.color = color
    }

    /// Init for multiple cycling texts.
    init(texts: [String], font: Font = Typography.tinyLabel, color: Color = ThemeColors.secondaryLabel) {
        self.texts = texts
        self.font = font
        self.color = color
    }

    var body: some View {
        GeometryReader { geo in
            let _ = updateContainerWidth(geo.size.width)
            Text(currentText)
                .id(currentIndex)
                .font(font)
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .background(
                    Text(currentText)
                        .font(font)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .hidden()
                        .overlay(GeometryReader { textGeo in
                            Color.clear.preference(key: TextWidthKey.self, value: textGeo.size.width)
                        })
                )
                .onPreferenceChange(TextWidthKey.self) { newWidth in
                    if abs(textWidth - newWidth) > 0.5 { textWidth = newWidth }
                }
                .offset(x: offset)
                .opacity(textOpacity)
        }
        .clipped()
        .frame(height: Layout.marqueeHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(texts.joined(separator: ", "))
        .accessibilityHint(texts.count > 1 ? "Cycles through \(texts.count) items" : "")
        .onChange(of: texts) { _ in restart() }
        .onAppear { beginCycle() }
        .onDisappear { cancelAndStop() }
    }

    // MARK: - Scheduling

    /// Schedule a block after a delay, cancelling any previous pending work.
    private func schedule(after delay: Double, _ action: @escaping () -> Void) {
        pendingWork?.cancel()
        let item = DispatchWorkItem { [self] in
            guard animating else { return }
            action()
        }
        pendingWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func cancelAndStop() {
        pendingWork?.cancel()
        pendingWork = nil
        animating = false
    }

    // MARK: - Layout

    private func updateContainerWidth(_ width: CGFloat) {
        if abs(containerWidth - width) > 1 {
            containerWidth = width
        }
    }

    // MARK: - Cycle control

    private func beginCycle() {
        guard !texts.isEmpty else { return }
        animating = true
        offset = 0
        textOpacity = 1.0

        // Wait a beat for geometry to settle, then decide scroll vs hold
        schedule(after: MotionConstants.marqueePauseSeconds) {
            if needsScroll {
                scrollLeft()
            } else if hasMultiple {
                holdThenAdvance()
            }
        }
    }

    private func restart() {
        cancelAndStop()
        offset = 0
        textWidth = 0
        currentIndex = 0
        textOpacity = 1.0
        schedule(after: MotionConstants.marqueeRestartSeconds) {
            beginCycle()
        }
    }

    // MARK: - Scrolling

    private func scrollLeft() {
        guard animating, needsScroll else { return }
        let travel = textWidth - containerWidth

        withAnimation(MotionConstants.marqueeScroll(travelPoints: Double(travel))) {
            offset = -travel
        }

        let duration = Double(travel) / MotionConstants.marqueeScrollSpeed
        schedule(after: duration + MotionConstants.marqueePauseSeconds) {
            if hasMultiple {
                fadeToNext()
            } else {
                scrollRight()
            }
        }
    }

    private func scrollRight() {
        guard animating, needsScroll else { return }
        let travel = textWidth - containerWidth

        withAnimation(MotionConstants.marqueeScroll(travelPoints: Double(travel))) {
            offset = 0
        }

        let duration = Double(travel) / MotionConstants.marqueeScrollSpeed
        schedule(after: duration + MotionConstants.marqueePauseSeconds) {
            scrollLeft()
        }
    }

    // MARK: - Multi-text cycling

    /// Hold the current (non-scrolling) text, then advance.
    private func holdThenAdvance() {
        schedule(after: MotionConstants.marqueeHoldSeconds) {
            fadeToNext()
        }
    }

    /// Cross-fade to the next text in the list.
    private func fadeToNext() {
        guard animating, hasMultiple else { return }

        // Fade out
        withAnimation(MotionConstants.fadeOut) {
            textOpacity = 0
        }

        // 0.35s lines up with fadeOut's 0.3s duration plus a brief settle.
        schedule(after: 0.35) {
            currentIndex = (currentIndex + 1) % texts.count
            offset = 0
            textWidth = 0

            // Fade in
            withAnimation(MotionConstants.fadeIn) {
                textOpacity = 1.0
            }

            // After fade-in + geometry settle, start new cycle for this text
            schedule(after: MotionConstants.marqueeFadeSettleSeconds) {
                if needsScroll {
                    scrollLeft()
                } else {
                    holdThenAdvance()
                }
            }
        }
    }
}

/// PreferenceKey for measuring text width without a nested GeometryReader.
private struct TextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
