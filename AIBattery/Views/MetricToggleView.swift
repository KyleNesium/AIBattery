import SwiftUI

struct MetricToggleView: View {
    @Binding var metricModeRaw: String
    let autoResolvedBinding: Binding<String>
    @AppStorage(UserDefaultsKeys.autoMetricMode) private var autoMetricMode: Bool = false
    let snapshot: UsageSnapshot?

    /// Cached ordered modes — avoids allocating a new array on every body evaluation.
    @State private var cachedOrderedModes: [MetricMode] = MetricMode.allCases

    var orderedModes: [MetricMode] { cachedOrderedModes }

    var body: some View {
        HStack(spacing: 8) {
            autoModeButton

            Picker("", selection: autoMetricMode ? autoResolvedBinding : $metricModeRaw) {
                ForEach(MetricMode.allCases, id: \.rawValue) { mode in
                    Text(mode.shortLabel).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .opacity(autoMetricMode ? 0.55 : 1.0)
            .disabled(autoMetricMode)
            .accessibilityLabel("Metric mode")
            .accessibilityHint("Switch between 5-hour, 7-day, and context health views")
            .help(autoMetricMode ? "Disabled while auto mode is active" : "Select primary metric for menu bar display")
        }
        .padding(.horizontal, Spacing.sectionHorizontal)
        .padding(.vertical, Spacing.section)
        .background(ThemeColors.badgeFill)
        .onAppear { recomputeOrderedModes() }
        .onChange(of: metricModeRaw) { _ in recomputeOrderedModes() }
    }

    @State private var autoHovered = false

    private var autoModeButton: some View {
        Button {
            withAnimation(MotionConstants.standard) {
                autoMetricMode.toggle()
            }
        } label: {
            Text("A")
                .font(Typography.autoModeLabel)
                .foregroundStyle(autoMetricMode ? Color.blue : autoHovered ? .secondary : .secondary.opacity(0.5))
                .frame(width: Layout.autoModeSize, height: Layout.autoModeSize)
                .background(
                    Circle()
                        .fill(autoMetricMode ? Color.blue.opacity(0.15) : autoHovered ? Color.primary.opacity(0.06) : Color.clear)
                )
                .overlay(
                    Circle()
                        .stroke(autoMetricMode ? Color.blue.opacity(0.6) : autoHovered ? Color.secondary.opacity(0.4) : Color.secondary.opacity(0.2), lineWidth: 1.5)
                )
                .shadow(color: autoMetricMode ? Color.blue.opacity(0.5) : .clear, radius: 4)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { autoHovered = $0 }
        .accessibilityLabel("Auto mode")
        .accessibilityValue(autoMetricMode ? "On" : "Off")
        .accessibilityHint("Automatically shows the highest usage metric")
        .help(autoMetricMode ? "Auto mode: showing highest metric" : "Enable auto mode")
        .onChange(of: autoMetricMode) { active in
            announceAutoMode(active)
        }
    }

    private func announceAutoMode(_ active: Bool) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: "Auto mode \(active ? "on" : "off")"]
        )
    }

    private func recomputeOrderedModes() {
        let currentMode: MetricMode
        if autoMetricMode, let snap = snapshot {
            currentMode = snap.autoResolvedMode
        } else {
            currentMode = MetricMode(rawValue: metricModeRaw) ?? .fiveHour
        }
        cachedOrderedModes = [currentMode] + MetricMode.allCases.filter { $0 != currentMode }
    }
}
