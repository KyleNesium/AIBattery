import SwiftUI

/// Refresh interval slider.
struct RefreshSettingsSection: View {
    let viewModel: UsageViewModel
    @AppStorage(UserDefaultsKeys.refreshInterval) private var refreshInterval: Double = 60

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                Text("Refresh")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
                Slider(value: $refreshInterval, in: 10...60, step: 5)
                    .onChange(of: refreshInterval) { _ in
                        viewModel.updatePollingInterval(refreshInterval)
                    }
                    .accessibilityLabel("Refresh interval")
                    .accessibilityValue("\(Int(refreshInterval)) seconds")
                Text("\(Int(refreshInterval))s")
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 28, alignment: .trailing)
            }
            sliderMarks(labels: ["10s", "20s", "30s", "40s", "50s", "60s"], leadingPad: 50)
            Text("~3 tokens per poll")
                .font(.caption2)
                .foregroundStyle(ThemeColors.tertiaryLabel)
                .padding(.leading, 58)
        }
    }
}

/// Tick mark labels displayed below a slider. Shared across settings sections.
func sliderMarks(labels: [String], leadingPad: CGFloat) -> some View {
    HStack {
        Spacer().frame(width: leadingPad + 8) // label width + HStack spacing
        HStack(spacing: 0) {
            ForEach(Array(labels.enumerated()), id: \.offset) { i, label in
                Text(label)
                    .font(.system(size: 8))
                    .foregroundStyle(ThemeColors.tertiaryLabel)
                if i < labels.count - 1 {
                    Spacer()
                }
            }
        }
        Spacer().frame(width: 36) // value label width + spacing
    }
}
