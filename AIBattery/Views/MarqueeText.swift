import SwiftUI

/// A news-ticker style text view that scrolls horizontally when text is wider than the container.
/// Supports multiple texts — cycles through them with fade transitions, scrolling each if needed.
/// Single text bounces back and forth; if the text fits, it displays statically.
struct MarqueeText: View {
    let texts: [String]
    var font: Font = .caption2
    var color: Color = .secondary

    @State private var currentIndex: Int = 0
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var animating = false
    @State private var textOpacity: Double = 1.0
    @State private var pendingWork: DispatchWorkItem?

    /// Pause at each end before scrolling.
    private let pauseDuration: Double = 2.0
    /// Points per second scroll speed.
    private let scrollSpeed: Double = 30.0
    /// How long a non-scrolling text stays before cycling to the next.
    private let holdDuration: Double = 3.0

    private var currentText: String {
        texts.isEmpty ? "" : texts[currentIndex % texts.count]
    }

    private var needsScroll: Bool { textWidth > containerWidth && containerWidth > 0 }
    private var hasMultiple: Bool { texts.count > 1 }

    /// Convenience init for a single text string.
    init(text: String, font: Font = .caption2, color: Color = .secondary) {
        self.texts = [text]
        self.font = font
        self.color = color
    }

    /// Init for multiple cycling texts.
    init(texts: [String], font: Font = .caption2, color: Color = .secondary) {
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
                    GeometryReader { textGeo in
                        Color.clear.onAppear { textWidth = textGeo.size.width }
                    }
                )
                .offset(x: offset)
                .opacity(textOpacity)
        }
        .clipped()
        .frame(height: 14)
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
            DispatchQueue.main.async { containerWidth = width }
        }
    }

    // MARK: - Cycle control

    private func beginCycle() {
        guard !texts.isEmpty else { return }
        animating = true
        offset = 0
        textOpacity = 1.0

        // Wait a beat for geometry to settle, then decide scroll vs hold
        schedule(after: pauseDuration) {
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
        schedule(after: 0.1) {
            beginCycle()
        }
    }

    // MARK: - Scrolling

    private func scrollLeft() {
        guard animating, needsScroll else { return }
        let travel = textWidth - containerWidth
        let duration = travel / scrollSpeed

        withAnimation(.linear(duration: duration)) {
            offset = -travel
        }

        schedule(after: duration + pauseDuration) {
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
        let duration = travel / scrollSpeed

        withAnimation(.linear(duration: duration)) {
            offset = 0
        }

        schedule(after: duration + pauseDuration) {
            scrollLeft()
        }
    }

    // MARK: - Multi-text cycling

    /// Hold the current (non-scrolling) text, then advance.
    private func holdThenAdvance() {
        schedule(after: holdDuration) {
            fadeToNext()
        }
    }

    /// Cross-fade to the next text in the list.
    private func fadeToNext() {
        guard animating, hasMultiple else { return }

        // Fade out
        withAnimation(.easeOut(duration: 0.3)) {
            textOpacity = 0
        }

        schedule(after: 0.35) {
            currentIndex = (currentIndex + 1) % texts.count
            offset = 0
            textWidth = 0

            // Fade in
            withAnimation(.easeIn(duration: 0.3)) {
                textOpacity = 1.0
            }

            // After fade-in + geometry settle, start new cycle for this text
            schedule(after: 0.6) {
                if needsScroll {
                    scrollLeft()
                } else {
                    holdThenAdvance()
                }
            }
        }
    }
}
