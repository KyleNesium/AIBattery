import SwiftUI

/// Display toggles + idle session cutoff slider.
struct DisplaySettingsSection: View {
    @AppStorage(UserDefaultsKeys.idleSessionMinutes) private var idleSessionMinutes: Double = 0
    @AppStorage(UserDefaultsKeys.colorblindMode) private var colorblindMode: Bool = false
    @AppStorage(UserDefaultsKeys.showAllAccountsInMenuBar) private var showAllAccountsInMenuBar: Bool = false
    @State private var idleSliderPosition: Double = 6
    /// Slider positions (1-6) mapped to minutes: 30, 60, 120, 240, 480, 0 (never).
    private static let idleSteps: [Double] = [30, 60, 120, 240, 480, 0]

    var body: some View {
        // Idle session cutoff (slider 1-6; positions map to 30m/1h/2h/4h/8h/Never)
        VStack(spacing: Spacing.tight) {
            HStack(spacing: Spacing.section) {
                Text("Hide idle")
                    .font(Typography.caption)
                    .foregroundStyle(ThemeColors.secondaryLabel)
                    .frame(width: Layout.settingsLabel, alignment: .trailing)
                Slider(value: $idleSliderPosition, in: 1...6, step: 1) { editing in
                    if !editing {
                        // Only write to AppStorage on drag end — avoids cascading redraws per tick
                        idleSessionMinutes = Self.idleSteps[max(0, min(Int(idleSliderPosition) - 1, Self.idleSteps.count - 1))]
                    }
                }
                .onAppear {
                    if let idx = Self.idleSteps.firstIndex(of: idleSessionMinutes) {
                        idleSliderPosition = Double(idx + 1)
                    } else {
                        idleSliderPosition = 6
                    }
                }
                .onChange(of: idleSessionMinutes) { newValue in
                    if let idx = Self.idleSteps.firstIndex(of: newValue) {
                        idleSliderPosition = Double(idx + 1)
                    }
                }
                .accessibilityLabel("Hide idle sessions")
                .accessibilityValue(idleLabelForPosition)
                Text(idleLabelForPosition)
                    .font(Typography.monoCaption)
                    .frame(width: Layout.sliderValueLabel, alignment: .trailing)
            }
            .help(idleSliderPosition >= 6 ? "Show all sessions regardless of idle time" : "Hide sessions idle longer than \(idleLabelForPosition)")
            sliderMarks(labels: ["30m", "1h", "2h", "4h", "8h", "\u{221E}"], leadingPad: Layout.settingsLabel)
        }

        // Display toggles
        VStack(alignment: .leading, spacing: Spacing.tight) {
            HStack(spacing: Spacing.section) {
                Text("Display")
                    .font(Typography.caption)
                    .foregroundStyle(ThemeColors.secondaryLabel)
                    .frame(width: Layout.settingsLabel, alignment: .trailing)
                Toggle("Colorblind", isOn: $colorblindMode)
                    .toggleStyle(.checkbox)
                    .font(Typography.caption)
                    .help("Use colorblind-safe palette (blue/cyan/amber/purple)")
            }
            HStack(spacing: Spacing.section) {
                Text("")
                    .font(Typography.caption)
                    .frame(width: Layout.settingsLabel, alignment: .trailing)
                Toggle("All accounts in menu bar", isOn: $showAllAccountsInMenuBar)
                    .toggleStyle(.checkbox)
                    .font(Typography.caption)
                    .help("Show every connected account's usage in the menu bar (e.g. 42% | 23%). Star color and countdown reflect the worst account.")
            }
        }
    }

    /// Display label for the current slider position (live during drag).
    private var idleLabelForPosition: String {
        let idx = max(0, min(Int(idleSliderPosition) - 1, Self.idleSteps.count - 1))
        let minutes = Self.idleSteps[idx]
        switch Int(minutes) {
        case 30: return "30m"
        case 60: return "1h"
        case 120: return "2h"
        case 240: return "4h"
        case 480: return "8h"
        default: return "\u{221E}"
        }
    }
}
