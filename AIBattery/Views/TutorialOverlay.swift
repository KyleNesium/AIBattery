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
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            // Centered card
            VStack(spacing: 16) {
                Image(systemName: steps[step].icon)
                    .font(.system(size: 28))
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)

                Text(steps[step].title)
                    .font(.headline)

                Text(steps[step].description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                // Step indicators
                HStack(spacing: 6) {
                    ForEach(0..<steps.count, id: \.self) { i in
                        Circle()
                            .fill(i == step ? Color.blue : Color.secondary.opacity(0.3))
                            .frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Step \(step + 1) of \(steps.count)")

                // Action buttons
                HStack {
                    if step < steps.count - 1 {
                        Button("Skip") {
                            withAnimation(.easeOut(duration: 0.2)) { hasSeenTutorial = true }
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Skip tutorial")
                    }

                    Spacer()

                    Button(step < steps.count - 1 ? "Next" : "Get Started") {
                        if step < steps.count - 1 {
                            withAnimation(.easeInOut(duration: 0.2)) { step += 1 }
                        } else {
                            withAnimation(.easeOut(duration: 0.2)) { hasSeenTutorial = true }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(24)
            .frame(maxWidth: 280)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Tutorial: \(steps[step].title)")
        }
    }
}
