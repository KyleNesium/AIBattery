import SwiftUI

/// 3-step walkthrough overlay shown on first data load.
/// Owns its own `hasSeenTutorial` @AppStorage — parent just passes `hasData`.
struct TutorialOverlay: View {
    let hasData: Bool
    @AppStorage(UserDefaultsKeys.hasSeenTutorial) private var hasSeenTutorial = false
    @State private var step = 0

    private let steps: [(title: String, description: String, icon: String)] = [
        (
            "Rate Limits",
            "The 5-hour and 7-day bars show your current usage against Anthropic's sliding window limits. The \"binding\" badge marks whichever window is constraining you.",
            "chart.bar.fill"
        ),
        (
            "Context Health",
            "Monitors your active Claude Code sessions. The gauge shows how much of the usable context window is consumed. Orange and red bands warn when quality may degrade.",
            "brain.head.profile"
        ),
        (
            "Settings",
            "Click the gear icon to customize refresh interval, toggle sections, enable alerts for outages and rate limits, and more.",
            "gearshape.fill"
        ),
    ]

    var body: some View {
        if !hasSeenTutorial && hasData {
            content
        }
    }

    private var content: some View {
        ZStack {
            // Semi-transparent backdrop
            Color.black.opacity(ThemeColors.overlayBackdropOpacity)
                .ignoresSafeArea()

            // Centered card
            VStack(spacing: Spacing.sectionHorizontal) {
                Image(systemName: steps[step].icon)
                    .font(Typography.largeIcon)
                    .foregroundStyle(ThemeColors.action)
                    .accessibilityHidden(true)

                Text(steps[step].title)
                    .font(Typography.sectionHeader)

                Text(steps[step].description)
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                // Step indicators
                HStack(spacing: Spacing.gap) {
                    ForEach(0..<steps.count, id: \.self) { i in
                        Circle()
                            .fill(i == step ? ThemeColors.action : Color.secondary.opacity(ThemeColors.inactiveIndicatorOpacity))
                            .frame(width: Layout.dotSizeSmall, height: Layout.dotSizeSmall)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Step \(step + 1) of \(steps.count)")

                // Action buttons
                HStack {
                    if step < steps.count - 1 {
                        Button("Skip") {
                            withAnimation(MotionConstants.dialog) { hasSeenTutorial = true }
                        }
                        .buttonStyle(.plain)
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                        .keyboardShortcut(.cancelAction)
                        .accessibilityLabel("Skip tutorial")
                        .help("Skip the tutorial walkthrough")
                        .onHover { inside in
                            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                        }
                    }

                    Spacer()

                    Button(step < steps.count - 1 ? "Next" : "Get Started") {
                        if step < steps.count - 1 {
                            withAnimation(MotionConstants.dialog) { step += 1 }
                        } else {
                            withAnimation(MotionConstants.dialog) { hasSeenTutorial = true }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(Spacing.overlay)
            .frame(maxWidth: 280)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Tutorial: \(steps[step].title)")
        }
    }
}
