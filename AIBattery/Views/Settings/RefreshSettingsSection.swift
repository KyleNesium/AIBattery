import SwiftUI

/// Refresh interval slider.
struct RefreshSettingsSection: View {
    let viewModel: UsageViewModel
    @AppStorage(UserDefaultsKeys.refreshInterval) private var refreshInterval: Double = 60
    @State private var sliderValue: Double = 60
    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                Text("Refresh")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: Layout.settingsLabel, alignment: .trailing)
                Slider(value: $sliderValue, in: 10...60, step: 5) { editing in
                    isDragging = editing
                    if !editing {
                        // Only update polling when drag ends — avoids timer restarts per tick
                        refreshInterval = sliderValue
                        viewModel.updatePollingInterval(sliderValue)
                    }
                }
                    .onAppear { sliderValue = refreshInterval }
                    .accessibilityLabel("Refresh interval")
                    .accessibilityValue("\(Int(sliderValue)) seconds")
                Text("\(Int(sliderValue))s")
                    .font(Typography.monoCaption)
                    .frame(width: 28, alignment: .trailing)
            }
            sliderMarks(labels: ["10s", "20s", "30s", "40s", "50s", "60s"], leadingPad: Layout.settingsLabel)
            Text("~3 tokens/poll to update menu bar")
                .font(Typography.tinyLabel)
                .foregroundStyle(ThemeColors.tertiaryLabel)
                .padding(.leading, Layout.settingsLabel + Spacing.section)
        }
    }
}

/// Tick mark labels displayed below a slider. Shared across settings sections.
/// `leadingPad` = label column width; adds HStack spacing (8pt) to align with slider track.
/// Trailing spacer accounts for value label (28pt) + HStack spacing (8pt).
func sliderMarks(labels: [String], leadingPad: CGFloat) -> some View {
    HStack {
        Spacer().frame(width: leadingPad + Spacing.section)
        HStack(spacing: 0) {
            ForEach(Array(labels.enumerated()), id: \.offset) { i, label in
                Text(label)
                    .font(Typography.decorativeIcon)
                    .foregroundStyle(ThemeColors.tertiaryLabel)
                if i < labels.count - 1 {
                    Spacer()
                }
            }
        }
        Spacer().frame(width: 36)
    }
}
