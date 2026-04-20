import SwiftUI

/// Refresh interval slider.
struct RefreshSettingsSection: View {
    let viewModel: UsageViewModel
    @AppStorage(UserDefaultsKeys.refreshInterval) private var refreshInterval: Double = 120
    @State private var sliderValue: Double = 120
    @State private var isDragging = false

    var body: some View {
        VStack(spacing: Spacing.tight) {
            HStack(spacing: Spacing.section) {
                Text("Refresh")
                    .font(Typography.caption)
                    .foregroundStyle(ThemeColors.secondaryLabel)
                    .frame(width: Layout.settingsLabel, alignment: .trailing)
                Slider(value: $sliderValue, in: 30...300, step: 30) { editing in
                    isDragging = editing
                    if !editing {
                        refreshInterval = sliderValue
                        viewModel.updatePollingInterval(sliderValue)
                    }
                }
                    .onAppear { sliderValue = refreshInterval }
                    .accessibilityLabel("Refresh interval")
                    .accessibilityValue(refreshLabel)
                Text(refreshLabel)
                    .font(Typography.monoCaption)
                    .frame(width: Layout.sliderValueLabel, alignment: .trailing)
            }
            .help("How often to poll the API for updated usage data (\(refreshLabel))")
            sliderMarks(labels: ["30s", "1m", "2m", "3m", "4m", "5m"], leadingPad: Layout.settingsLabel)
            Text("~3 tokens/poll · API data kept until next update")
                .font(Typography.tinyLabel)
                .foregroundStyle(ThemeColors.tertiaryLabel)
                .padding(.leading, Layout.settingsLabel + Spacing.section)
        }
    }

    private var refreshLabel: String {
        let secs = Int(sliderValue)
        if secs >= 60 {
            let mins = secs / 60
            let remainder = secs % 60
            return remainder == 0 ? "\(mins)m" : "\(mins)m\(remainder)s"
        }
        return "\(secs)s"
    }
}

/// Tick mark labels displayed below a slider. Shared across settings sections.
/// `leadingPad` = label column width; adds HStack spacing (8pt) to align with slider track.
/// Trailing spacer accounts for value label + HStack spacing.
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
        Spacer().frame(width: Layout.sliderValueLabel + Spacing.section)
    }
}
