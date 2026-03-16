import SwiftUI

/// Display toggles + idle session cutoff slider.
struct DisplaySettingsSection: View {
    @AppStorage(UserDefaultsKeys.idleSessionMinutes) private var idleSessionMinutes: Double = 0
    @AppStorage(UserDefaultsKeys.colorblindMode) private var colorblindMode: Bool = false
    @State private var idleSliderPosition: Double = 6
    /// Slider positions (1-6) mapped to minutes: 30, 60, 120, 240, 480, 0 (never).
    private static let idleSteps: [Double] = [30, 60, 120, 240, 480, 0]

    var body: some View {
        // Idle session cutoff (slider 1-6; positions map to 30m/1h/2h/4h/8h/Never)
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                Text("Hide idle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
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
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 28, alignment: .trailing)
                    .help(idleSliderPosition >= 6 ? "Show all sessions" : "Hide sessions idle > \(idleLabelForPosition)")
            }
            sliderMarks(labels: ["30m", "1h", "2h", "4h", "8h", "\u{221E}"], leadingPad: 50)
        }

        // Display toggles
        HStack(spacing: 8) {
            Text("Display")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
            Toggle("Colorblind", isOn: $colorblindMode)
                .toggleStyle(.checkbox)
                .font(.caption)
                .help("Use colorblind-safe palette (blue/cyan/amber/purple)")
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
