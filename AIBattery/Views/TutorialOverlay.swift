import SwiftUI

/// 3-step walkthrough overlay shown on first data load.
/// Owns its own `hasSeenTutorial` @AppStorage — parent just passes `hasData`.
struct TutorialOverlay: View {
    let hasData: Bool
    /// Shape of the active account's quota — step 1 describes the bar the user is
    /// actually looking at (windows, a Credits budget, or per-minute API limits).
    var kind: CodexDisplayKind = .windows
    @AppStorage(UserDefaultsKeys.hasSeenTutorial) private var hasSeenTutorial = false
    @State private var step = 0

    /// Step-1 copy per quota shape. Exposed for tests.
    nonisolated static func rateLimitStep(kind: CodexDisplayKind) -> (title: String, description: String, icon: String) {
        switch kind {
        case .windows:
            (
                "Rate Limits",
                "The 5-hour and 7-day (Weekly for Codex) bars show your current usage against your provider's sliding window limits. The \"binding\" badge marks whichever window is constraining you.",
                "chart.bar.fill"
            )
        case .credits:
            (
                "Credits",
                "The Credits bar shows how much of this period's spend budget your workspace has used, with the remaining credits and when the budget resets.",
                "creditcard.fill"
            )
        case .apiLimits:
            (
                "API Limits",
                "The Requests and Tokens bars show OpenAI's per-minute limits for your API key. Costs below are your real bill at API rates.",
                "key.fill"
            )
        }
    }

    private var steps: [(title: String, description: String, icon: String)] { [
        Self.rateLimitStep(kind: kind),
        (
            "Context Health",
            "Monitors your active Claude Code or Codex sessions. The gauge shows how much of the usable context window is consumed. Orange and red bands warn when quality may degrade.",
            "brain.head.profile"
        ),
        (
            "Settings",
            "Click the gear icon to customize refresh interval, toggle sections, enable alerts for outages and rate limits, and more.",
            "gearshape.fill"
        ),
    ] }

    var body: some View {
        if !hasSeenTutorial && hasData {
            content
        }
    }

    private var content: some View {
        ZStack {
            // Semi-transparent backdrop
            ThemeColors.shadowColor.opacity(ThemeColors.overlayBackdropOpacity)
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
                    .foregroundStyle(ThemeColors.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                // Step indicators
                HStack(spacing: Spacing.gap) {
                    ForEach(0..<steps.count, id: \.self) { i in
                        Circle()
                            .fill(i == step ? ThemeColors.action : ThemeColors.inactiveStroke.opacity(ThemeColors.inactiveIndicatorOpacity))
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
                        .foregroundStyle(ThemeColors.secondaryLabel)
                        .keyboardShortcut(.cancelAction)
                        .accessibilityLabel("Skip tutorial")
                        .help("Skip the tutorial walkthrough")
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
            .frame(maxWidth: Layout.tutorialCardMaxWidth)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Tutorial: \(steps[step].title)")
        }
    }
}
