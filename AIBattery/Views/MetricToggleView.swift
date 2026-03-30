import SwiftUI

struct MetricToggleView: View {
    /// Single stable binding that routes auto/manual mode internally.
    /// Avoids the SwiftUI AttributeGraph crash from swapping Binding instances.
    let pickerBinding: Binding<String>
    @AppStorage(UserDefaultsKeys.autoMetricMode) private var autoMetricMode: Bool = false
    let snapshot: UsageSnapshot?

    /// Cached ordered modes — avoids allocating a new array on every body evaluation.
    @State private var cachedOrderedModes: [MetricMode] = MetricMode.allCases

    var orderedModes: [MetricMode] { cachedOrderedModes }

    var body: some View {
        HStack(spacing: Spacing.gap) {
            autoModeButton

            ForEach(MetricMode.allCases, id: \.rawValue) { mode in
                tabButton(for: mode)
            }
        }
        .padding(.horizontal, Spacing.sectionHorizontal)
        .padding(.vertical, Spacing.gap)
        .accessibilityLabel("Metric mode")
        .accessibilityHint("Switch between 5-hour, 7-day, and context health views")
        .help(autoMetricMode ? "Disabled while auto mode is active" : "Select primary metric for menu bar display")
        .onAppear { recomputeOrderedModes() }
        .onChange(of: pickerBinding.wrappedValue) { _ in recomputeOrderedModes() }
    }

    // MARK: - Tab Button

    @State private var hoveredMode: MetricMode?

    /// Raised segment fill — must be visibly brighter than the trackFill container.
    private static let selectedFill: Color = ThemeColors.adaptive(
        light: NSColor(white: 1.0, alpha: 0.9),
        dark: NSColor(white: 1.0, alpha: 0.18)
    )

    private func tabButton(for mode: MetricMode) -> some View {
        let isSelected = pickerBinding.wrappedValue == mode.rawValue
        let isHovered = hoveredMode == mode && !isSelected

        return Button {
            withAnimation(MotionConstants.snappy) {
                // Disable auto mode first, then write directly to the raw
                // AppStorage key — the pickerBinding setter guards on
                // autoMetricMode which may not have propagated yet.
                autoMetricMode = false
                UserDefaults.standard.set(mode.rawValue, forKey: UserDefaultsKeys.metricMode)
            }
        } label: {
            Text(mode.shortLabel)
                .font(Typography.caption)
                .foregroundStyle(isSelected && !autoMetricMode ? .primary : ThemeColors.secondaryLabel)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.small)
                .background(
                    RoundedRectangle(cornerRadius: Spacing.small)
                        .fill(isSelected && !autoMetricMode ? Self.selectedFill : isHovered ? ThemeColors.hoverFill : .clear)
                        .shadow(color: isSelected && !autoMetricMode ? Color.black.opacity(0.25) : .clear, radius: 1, y: 0.5)
                )
                .contentShape(RoundedRectangle(cornerRadius: Spacing.small))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredMode = hovering ? mode : nil
        }
    }

    // MARK: - Auto Mode Button

    @State private var autoHovered = false

    private var autoModeButton: some View {
        Button {
            withAnimation(MotionConstants.standard) {
                autoMetricMode.toggle()
            }
        } label: {
            Text("A")
                .font(Typography.autoModeLabel)
                .foregroundStyle(autoMetricMode ? ThemeColors.action : autoHovered ? .secondary : .secondary.opacity(0.5))
                .frame(width: Layout.autoModeSize, height: Layout.autoModeSize)
                .background(
                    Circle()
                        .fill(autoMetricMode ? ThemeColors.action.opacity(0.15) : autoHovered ? ThemeColors.hoverFill : .clear)
                )
                .overlay(
                    Circle()
                        .stroke(autoMetricMode ? ThemeColors.action.opacity(0.6) : autoHovered ? Color.secondary.opacity(0.4) : Color.secondary.opacity(0.2), lineWidth: 1.5)
                )
                .shadow(color: autoMetricMode ? ThemeColors.action.opacity(0.5) : .clear, radius: 4)
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

    // MARK: - Helpers

    private func announceAutoMode(_ active: Bool) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: "Auto mode \(active ? "on" : "off")"]
        )
    }

    private func recomputeOrderedModes() {
        let currentMode = MetricMode(rawValue: pickerBinding.wrappedValue) ?? .fiveHour
        cachedOrderedModes = [currentMode] + MetricMode.allCases.filter { $0 != currentMode }
    }
}
