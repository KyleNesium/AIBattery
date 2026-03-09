import SwiftUI

/// Display toggles + idle session cutoff slider.
struct DisplaySettingsSection: View {
    @AppStorage(UserDefaultsKeys.idleSessionMinutes) private var idleSessionMinutes: Double = 0
    @AppStorage(UserDefaultsKeys.colorblindMode) private var colorblindMode: Bool = false
    @AppStorage(UserDefaultsKeys.showCostEstimate) private var showCostEstimate: Bool = false

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
                Slider(value: idleSliderBinding, in: 1...6, step: 1)
                    .accessibilityLabel("Hide idle sessions")
                    .accessibilityValue(idleLabel)
                Text(idleLabel)
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 28, alignment: .trailing)
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
            Toggle("Cost", isOn: $showCostEstimate)
                .toggleStyle(.checkbox)
                .font(.caption)
        }
    }

    /// Maps slider position (1-6) <-> stored minutes (30/60/120/240/480/0).
    private var idleSliderBinding: Binding<Double> {
        Binding(
            get: {
                if let idx = Self.idleSteps.firstIndex(of: idleSessionMinutes) {
                    return Double(idx + 1)
                }
                return 6 // default to "Never"
            },
            set: { idleSessionMinutes = Self.idleSteps[max(0, min(Int($0) - 1, Self.idleSteps.count - 1))] }
        )
    }

    /// Display label for the current idle cutoff.
    private var idleLabel: String {
        switch Int(idleSessionMinutes) {
        case 30: return "30m"
        case 60: return "1h"
        case 120: return "2h"
        case 240: return "4h"
        case 480: return "8h"
        default: return "\u{221E}"
        }
    }
}
