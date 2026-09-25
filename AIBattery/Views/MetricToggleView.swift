import SwiftUI

struct MetricToggleView: View {
    /// Single stable binding that routes auto/manual mode internally.
    /// Avoids the SwiftUI AttributeGraph crash from swapping Binding instances.
    let pickerBinding: Binding<String>
    @AppStorage(UserDefaultsKeys.autoMetricMode) private var autoMetricMode: Bool = false
    let snapshot: UsageSnapshot?
    /// Active provider + the shape of its quota — drives tab labels
    /// ("7 Day" / "Weekly" / "Credits" / "API Limits") and which tabs exist.
    var provider: AIProvider = .claude
    var kind: CodexDisplayKind = .windows
    private var collapsed: Bool { kind != .windows }

    /// Cached ordered modes — avoids allocating a new array on every body evaluation.
    @State private var cachedOrderedModes: [MetricMode] = MetricMode.allCases

    var orderedModes: [MetricMode] { cachedOrderedModes }

    var body: some View {
        HStack(spacing: 0) {
            autoModeButton
                .padding(.trailing, Spacing.section)

            HStack(spacing: Spacing.small) {
                ForEach(MetricMode.pickerModes(provider: provider, kind: kind), id: \.rawValue) { mode in
                    tabButton(for: mode)
                }
            }
        }
        .padding(.horizontal, Spacing.sectionHorizontal)
        .padding(.vertical, Spacing.gap)
        .accessibilityLabel("Metric mode")
        .accessibilityHint(collapsed ? "Switch between \(MetricMode.fiveHour.shortLabel(provider: provider, kind: kind).lowercased()) and context health views" : "Switch between 5-hour, \(provider.secondaryWindowLabel.lowercased()), and context health views")
        .help(autoMetricMode ? "Disabled while auto mode is active" : "Select primary metric (keys: 1, 2, 3)")
        .onAppear { recomputeOrderedModes() }
        .onChange(of: pickerBinding.wrappedValue) { _ in recomputeOrderedModes() }
    }

    // MARK: - Tab Button

    @State private var hoveredMode: MetricMode?

    /// Raised segment fill — uses the surface elevation token for raised interactive elements.
    private static let selectedFill: Color = ThemeColors.surfaceLevel2

    private func tabButton(for mode: MetricMode) -> some View {
        // In a collapsed layout the .sevenDay mode is hidden but may still be the stored
        // selection — treat it as the single-budget tab so the highlight doesn't vanish.
        let selectedRaw = pickerBinding.wrappedValue
        let isSelected = selectedRaw == mode.rawValue
            || (collapsed && mode == .fiveHour && selectedRaw == MetricMode.sevenDay.rawValue)
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
            Text(mode.shortLabel(provider: provider, kind: kind))
                .font(Typography.caption)
                .foregroundStyle(isSelected && !autoMetricMode ? .primary : ThemeColors.secondaryLabel)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.small)
                .background(
                    RoundedRectangle(cornerRadius: Layout.tabCornerRadius)
                        .fill(isSelected && !autoMetricMode ? Self.selectedFill : isHovered ? ThemeColors.hoverFill : .clear)
                        .shadow(color: isSelected && !autoMetricMode ? ThemeColors.shadowColor.opacity(ThemeColors.shadowOpacity) : .clear, radius: Layout.shadowSmall, y: 0.5)
                )
                .contentShape(RoundedRectangle(cornerRadius: Layout.tabCornerRadius))
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
                .foregroundStyle(autoMetricMode ? ThemeColors.action : autoHovered ? .secondary : .secondary.opacity(ThemeColors.activeLabelOpacity))
                .frame(width: Layout.autoModeSize, height: Layout.autoModeSize)
                .background(
                    Circle()
                        .fill(autoMetricMode ? ThemeColors.action.opacity(ThemeColors.activeElementFillOpacity) : autoHovered ? ThemeColors.hoverFill : .clear)
                )
                .overlay(
                    Circle()
                        .stroke(autoMetricMode ? ThemeColors.action.opacity(ThemeColors.activeAccentOpacity) : autoHovered ? ThemeColors.inactiveStroke.opacity(ThemeColors.hoverBorderOpacity) : ThemeColors.inactiveStroke.opacity(ThemeColors.subtleBorderOpacity), lineWidth: Layout.borderWidth)
                )
                .shadow(color: autoMetricMode ? ThemeColors.action.opacity(ThemeColors.activeLabelOpacity) : .clear, radius: Layout.glowRadius)
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
        cachedOrderedModes = MetricMode.orderedModes(current: currentMode)
    }
}
