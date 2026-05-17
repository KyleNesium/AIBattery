import SwiftUI

struct TokenHealthSection: View {
    let sessions: [TokenHealthStatus]
    var onRefresh: (() -> Void)? = nil
    @State private var selectedIndex: Int = 0
    @AppStorage(UserDefaultsKeys.contextCollapsed) private var collapsed: Bool = true

    /// Convenience init for single session (backward compat)
    init(health: TokenHealthStatus, onRefresh: (() -> Void)? = nil) {
        self.sessions = [health]
        self.onRefresh = onRefresh
    }

    init(sessions: [TokenHealthStatus], onRefresh: (() -> Void)? = nil) {
        self.sessions = sessions
        self.onRefresh = onRefresh
    }

    private var health: TokenHealthStatus {
        guard !sessions.isEmpty else {
            // Shouldn't happen — callers guard for empty sessions — but avoid a crash.
            return TokenHealthStatus.empty
        }
        let idx = min(selectedIndex, sessions.count - 1)
        return sessions[idx]
    }

    private var remainingText: String { TokenFormatter.format(health.remainingTokens) }
    private var usableText: String { TokenFormatter.format(health.usableWindow) }
    private var modelDisplay: String { health.model.isEmpty ? "unknown" : ModelNameMapper.displayName(for: health.model) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.gap) {
            // Header with session toggle
            HStack {
                CollapsibleSectionHeader(
                    title: "Context",
                    collapsed: $collapsed,
                    tooltip: "Context: \(Int(health.usagePercentage))% used \u{00B7} ~\(remainingText) of \(usableText) remaining\(sessions.count > 1 ? " \u{00B7} \(sessions.count) sessions (← → to browse)" : "")"
                )
                Spacer()

                if collapsed, let hash = sessionIdPrefix {
                    Text(hash)
                        .font(Typography.monoTiny)
                        .foregroundStyle(ThemeColors.tertiaryLabel)
                        .copyable(health.id)
                        .padding(.trailing, Spacing.inner)
                }

                if !collapsed && sessions.count > 1 {
                    sessionToggle
                }

                if !collapsed, let onRefresh {
                    RefreshButton(action: onRefresh)
                }
                healthBadge
            }

            if !collapsed {
                VStack(alignment: .leading, spacing: Spacing.gap) {
                    // Session info on its own line for full width
                    sessionInfoLabel
                        .id(selectedIndex)
                        .transition(.opacity)

                    // Gauge bar
                    GaugeBar(percent: health.usagePercentage, barColor: bandColor)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Context usage \(Int(health.usagePercentage)) percent")
                        .accessibilityValue("\(remainingText) tokens remaining")

                    // Detail row
                    HStack {
                        let detailText = "~\(remainingText) of \(usableText) usable"
                        Text(detailText)
                            .font(Typography.caption)
                            .foregroundStyle(ThemeColors.secondaryLabel)
                            .copyable(detailText)
                        Spacer()
                        let turnsModelText = "\(health.turnCount) turns · \(modelDisplay)"
                        Text(turnsModelText)
                            .font(Typography.tinyLabel)
                            .foregroundStyle(ThemeColors.tertiaryLabel)
                            .help("Conversation turns in this session")
                            .copyable(turnsModelText)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("~\(remainingText) of \(usableText) usable, \(health.turnCount) turns, \(health.model.isEmpty ? "unknown model" : modelDisplay)")

                    // Recommended minimum context hint
                    if health.band == .orange || health.band == .red {
                        let safeMin = health.usableWindow / 5 // 20% of usable window
                        Text("(keep above ~\(TokenFormatter.format(safeMin)) for best quality)")
                            .font(Typography.tinyLabel)
                            .foregroundStyle(ThemeColors.tertiaryLabel)
                            .help("Recommended minimum tokens to maintain response quality")
                    }

                    // Warnings — tiered by severity
                    ForEach(health.warnings) { warning in
                        HStack(spacing: Spacing.inner) {
                            Image(systemName: warningIcon(warning.severity))
                                .font(Typography.tinyLabel)
                                .foregroundStyle(warningIconColor(warning.severity))
                            Text(warning.message)
                                .font(Typography.tinyLabel)
                                .foregroundStyle(warningTextColor(warning.severity))
                        }
                        .help(warning.suggestion ?? "")
                    }

                    // Suggested action
                    if let action = health.suggestedAction {
                        Text(action)
                            .font(Typography.tinyLabel)
                            .foregroundStyle(health.band == .red ? ThemeColors.danger : ThemeColors.caution)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, Spacing.tight)
                    }
                }
                .transition(MotionConstants.expandTransition)
            }
        }
        .padding(.horizontal, Spacing.sectionHorizontal)
        .padding(.vertical, Spacing.section)
        .contentShape(Rectangle())
        .gesture(
            sessions.count > 1 ?
                DragGesture(minimumDistance: 20)
                .onEnded { value in
                    let horizontal = value.translation.width
                    guard abs(horizontal) > abs(value.translation.height) else { return }
                    // Accept either a long drag (>50pt) or a fast flick (velocity > 300pt/s)
                    let velocity = abs(value.predictedEndTranslation.width - value.translation.width)
                    guard abs(horizontal) > 50 || velocity > 300 else { return }
                    withAnimation(MotionConstants.snappy) {
                        if horizontal < 0 {
                            selectedIndex = min(selectedIndex + 1, sessions.count - 1)
                        } else {
                            selectedIndex = max(selectedIndex - 1, 0)
                        }
                    }
                }
                : nil
        )
        .accessibilityHint(sessions.count > 1 ? "Swipe left or right to browse sessions" : "")
        .onReceive(NotificationCenter.default.publisher(for: .panelKeyPress)) { notification in
            guard sessions.count > 1, let key = notification.object as? String else { return }
            withAnimation(MotionConstants.snappy) {
                if key == "right" {
                    selectedIndex = min(selectedIndex + 1, sessions.count - 1)
                } else if key == "left" {
                    selectedIndex = max(selectedIndex - 1, 0)
                }
            }
        }
        .onAppear { recomputeSessionInfo() }
        .onChange(of: selectedIndex) { _ in recomputeSessionInfo() }
        .onChange(of: sessions) { _ in recomputeSessionInfo() }
        .onChange(of: sessions.count) { newCount in
            if selectedIndex >= newCount {
                selectedIndex = 0
            }
        }
        .accessibilityAdjustableAction { direction in
            guard sessions.count > 1 else { return }
            withAnimation(MotionConstants.snappy) {
                switch direction {
                case .increment:
                    selectedIndex = min(selectedIndex + 1, sessions.count - 1)
                case .decrement:
                    selectedIndex = max(selectedIndex - 1, 0)
                @unknown default:
                    break
                }
            }
        }
    }

    /// Chevron buttons to cycle through sessions
    private var sessionToggle: some View {
        HStack(spacing: Spacing.tight) {
            ChevronButton(
                direction: .left,
                enabled: selectedIndex > 0
            ) {
                withAnimation(MotionConstants.snappy) {
                    selectedIndex = max(selectedIndex - 1, 0)
                }
            }
            .accessibilityLabel("Previous session")
            .accessibilityHint("Browses to the previous recent session")

            Text("\(selectedIndex + 1)/\(sessions.count)")
                .font(Typography.monoCaptionSmall)
                .foregroundStyle(ThemeColors.tertiaryLabel)

            ChevronButton(
                direction: .right,
                enabled: selectedIndex < sessions.count - 1
            ) {
                withAnimation(MotionConstants.snappy) {
                    selectedIndex = min(selectedIndex + 1, sessions.count - 1)
                }
            }
            .accessibilityLabel("Next session")
            .accessibilityHint("Browses to the next recent session")
        }
        .help("Browse recent sessions (← → arrow keys)")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Session \(selectedIndex + 1) of \(sessions.count)")
    }

    private var sessionInfoLabel: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            // Line 1: project · branch · session ID prefix + stale badge
            HStack(spacing: Spacing.inner) {
                let labelParts = sessionLabelParts
                let idPrefix = sessionIdPrefix
                if labelParts.isEmpty && idPrefix == nil {
                    Text("Latest session")
                        .font(Typography.tinyLabel)
                        .foregroundStyle(ThemeColors.tertiaryLabel)
                        .lineLimit(1)
                } else {
                    HStack(spacing: 0) {
                        if !labelParts.isEmpty {
                            Text(labelParts.joined(separator: " · "))
                                .font(Typography.tinyLabel)
                                .foregroundStyle(ThemeColors.tertiaryLabel)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        if let idPrefix {
                            if !labelParts.isEmpty {
                                Text(" · ")
                                    .font(Typography.tinyLabel)
                                    .foregroundStyle(ThemeColors.tertiaryLabel)
                            }
                            Text(idPrefix)
                                .font(Typography.tinyLabel)
                                .foregroundStyle(ThemeColors.tertiaryLabel)
                                .copyable(health.id)
                        }
                    }
                    .lineLimit(1)
                }

                if let idleMinutes = staleIdleMinutes {
                    HStack(spacing: Spacing.tight) {
                        Circle()
                            .fill(ThemeColors.caution)
                            .frame(width: Layout.dotSizeSmall, height: Layout.dotSizeSmall)
                        Text("Idle \(idleMinutes)m")
                            .font(Typography.monoCaptionSmall)
                            .foregroundStyle(ThemeColors.caution)
                    }
                    .help("Session has been idle — context may be stale")
                }
            }

            // Line 2: duration · last active · velocity
            let bottomParts = sessionBottomParts
            if !bottomParts.isEmpty {
                let bottomText = bottomParts.joined(separator: " · ")
                Text(bottomText)
                    .font(Typography.tinyLabel)
                    .foregroundStyle(ThemeColors.secondaryLabel)
                    .lineLimit(1)
                    .copyable(bottomText)
            }
        }
        .help(sessionDetailTooltip)
    }

    // Session detail helpers — cached to avoid recomputation on every body evaluation.
    // Recomputed via onChange(of: selectedIndex) and onChange(of: sessions).

    @State private var staleIdleMinutes: Int? = nil
    @State private var sessionDetailTooltip: String = ""
    @State private var sessionLabelParts: [String] = []
    @State private var sessionIdPrefix: String? = nil
    @State private var sessionBottomParts: [String] = []

    private func recomputeSessionInfo() {
        let h = health
        staleIdleMinutes = SessionInfoFormatter.staleIdleMinutes(for: h)
        sessionDetailTooltip = SessionInfoFormatter.detailTooltip(for: h)
        sessionLabelParts = SessionInfoFormatter.labelParts(for: h)
        sessionIdPrefix = SessionInfoFormatter.idPrefix(for: h)
        sessionBottomParts = SessionInfoFormatter.bottomParts(for: h)
    }

    private var healthBadge: some View {
        HStack(spacing: Spacing.inner) {
            Circle()
                .fill(bandColor)
                .frame(width: Layout.dotSize, height: Layout.dotSize)
                .animation(MotionConstants.smooth, value: bandColor)
                .accessibilityLabel("Health: \(health.band == .green ? "good" : health.band == .orange ? "warning" : health.band == .red ? "critical" : "unknown")")
            Text("\(Int(health.usagePercentage))%")
                .font(Typography.monoValue)
                .copyable("\(Int(health.usagePercentage))%")
        }
    }

    private var bandColor: Color {
        ThemeColors.bandColor(health.band)
    }

    // MARK: - Warning severity display helpers

    private func warningIcon(_ severity: HealthWarning.WarningSeverity) -> String {
        switch severity {
        case .strong: "exclamationmark.triangle.fill"
        case .mild: "exclamationmark.triangle"
        case .info: "info.circle"
        }
    }

    private func warningIconColor(_ severity: HealthWarning.WarningSeverity) -> Color {
        switch severity {
        case .strong: ThemeColors.danger
        case .mild: ThemeColors.caution
        case .info: ThemeColors.tertiaryLabel
        }
    }

    private func warningTextColor(_ severity: HealthWarning.WarningSeverity) -> Color {
        switch severity {
        case .strong, .mild: ThemeColors.secondaryLabel
        case .info: ThemeColors.tertiaryLabel
        }
    }
}

// MARK: - Chevron button with larger hit target and press highlight

private struct ChevronButton: View {
    enum Direction { case left, right }

    let direction: Direction
    let enabled: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: direction == .left ? "chevron.left" : "chevron.right")
                .font(Typography.chevronIcon)
                .frame(width: Layout.chevronFrame, height: Layout.chevronFrame)
                .background(
                    RoundedRectangle(cornerRadius: Layout.smallCornerRadius)
                        .fill(isPressed ? ThemeColors.hoverFill : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.primary.opacity(ThemeColors.enabledControlOpacity) : Color.primary.opacity(ThemeColors.disabledDeepOpacity))
        .disabled(!enabled)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}
