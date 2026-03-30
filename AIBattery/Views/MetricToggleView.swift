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
        HStack(spacing: 0) {
            autoModeButton
                .padding(.horizontal, Spacing.gap)

            // Vertical divider between auto button and tabs
            Color.secondary.opacity(0.2)
                .frame(width: 1, height: 14)

            // Custom tab buttons
            HStack(spacing: Spacing.tight) {
                ForEach(MetricMode.allCases, id: \.rawValue) { mode in
                    tabButton(for: mode)
                }
            }
            .padding(.horizontal, Spacing.small)
            .opacity(autoMetricMode ? ThemeColors.disabledOpacity : 1.0)
            .disabled(autoMetricMode)
            .accessibilityLabel("Metric mode")
            .accessibilityHint("Switch between 5-hour, 7-day, and context health views")
            .help(autoMetricMode ? "Disabled while auto mode is active" : "Select primary metric for menu bar display")
        }
        .padding(.vertical, Spacing.small)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(ThemeColors.trackFill.opacity(0.5))
        )
        .padding(.horizontal, Spacing.sectionHorizontal)
        .padding(.vertical, Spacing.section)
        .onAppear { recomputeOrderedModes() }
        .onChange(of: pickerBinding.wrappedValue) { _ in recomputeOrderedModes() }
    }

    // MARK: - Tab Button

    @State private var hoveredMode: MetricMode?

    private func tabButton(for mode: MetricMode) -> some View {
        let isSelected = pickerBinding.wrappedValue == mode.rawValue
        let isHovered = hoveredMode == mode && !isSelected

        return Button {
            withAnimation(MotionConstants.standard) {
                pickerBinding.wrappedValue = mode.rawValue
            }
        } label: {
            Text(mode.shortLabel)
                .font(isSelected ? Typography.bodyLabel : Typography.base)
                .foregroundStyle(isSelected ? ThemeColors.action : ThemeColors.secondaryLabel)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.small)
                .padding(.horizontal, Spacing.gap)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(tabBackground(isSelected: isSelected, isHovered: isHovered))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(
                            isSelected ? ThemeColors.action.opacity(0.4) : Color.clear,
                            lineWidth: 0.5
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredMode = hovering ? mode : nil
        }
    }

    private func tabBackground(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            return ThemeColors.action.opacity(0.2)
        } else if isHovered {
            return ThemeColors.hoverFill
        }
        return Color.clear
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
                        .fill(autoMetricMode ? ThemeColors.action.opacity(0.15) : autoHovered ? ThemeColors.hoverFill : Color.clear)
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
