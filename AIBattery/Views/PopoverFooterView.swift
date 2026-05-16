import SwiftUI

struct PopoverFooterView: View {
    let systemStatus: ClaudeSystemStatus?
    let isLoading: Bool
    let lastFreshFetch: Date?
    var isShowingCachedData: Bool = false
    let rateLimitSource: RateLimitSource?
    let footerMessage: String?
    @Binding var showLogoutConfirm: Bool
    let onLogout: () -> Void
    let onRequestLogout: () -> Void
    var body: some View {
        VStack(spacing: Spacing.gap) {
            // Links row
            HStack(spacing: Spacing.medium) {
                // Usage Dashboard
                FooterLink(
                    icon: "chart.bar",
                    label: "Usage",
                    tooltip: "Open usage dashboard in browser"
                ) {
                    if let url = URL(string: "https://claude.ai/settings/usage") {
                        NSWorkspace.shared.open(url)
                    }
                }

                // Status Page — colored dot acts as status indicator
                FooterLink(
                    label: "Status",
                    tooltip: statusTooltip,
                    accessibilityLabel: "System status: \(statusTooltip)"
                ) {
                    if let url = URL(string: StatusChecker.statusPageBaseURL) {
                        NSWorkspace.shared.open(url)
                    }
                } leading: {
                    statusDot
                }

                Spacer()

                // Logout (active account) — two-tap confirmation
                FooterLink(
                    icon: showLogoutConfirm ? "exclamationmark.triangle" : "rectangle.portrait.and.arrow.right",
                    label: showLogoutConfirm ? "Confirm?" : "Logout",
                    accessibilityLabel: showLogoutConfirm ? "Confirm logout" : "Logout",
                    accessibilityHint: "Sign out of active Claude account",
                    showsExternalArrow: false,
                    foregroundOverride: showLogoutConfirm ? ThemeColors.danger : nil,
                    action: {
                        if showLogoutConfirm {
                            onLogout()
                        } else {
                            onRequestLogout()
                        }
                    }
                )
                .animation(MotionConstants.snappy, value: showLogoutConfirm)

                // Quit
                FooterLink(
                    icon: "xmark.circle",
                    label: "Quit",
                    tooltip: "Quit (⌘Q)",
                    accessibilityLabel: "Quit AI Battery",
                    accessibilityHint: "Quit application",
                    showsExternalArrow: false,
                    foregroundOverride: ThemeColors.secondaryLabel,
                    action: { NSApplication.shared.terminate(nil) }
                )
            }

            // Active incident banner replaces timestamp when visible
            if let names = systemStatus?.incidentNames, !names.isEmpty {
                HStack(spacing: Spacing.inner) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(Typography.tinyLabel)
                        .foregroundStyle(statusColor)
                    MarqueeText(texts: names, color: statusColor)
                }
            } else {
                VStack(alignment: .leading, spacing: Spacing.micro) {
                    HStack {
                        Spacer()
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.4)
                                .frame(width: Layout.spinnerSize, height: Layout.spinnerSize)
                        }
                        if let lastFetch = lastFreshFetch {
                            RelativeTimeText(
                                date: lastFetch,
                                isStale: isShowingCachedData
                            )
                        } else if isLoading {
                            Text("Updating…")
                                .font(Typography.monoTiny)
                                .foregroundStyle(ThemeColors.tertiaryLabel)
                        }
                    }
                    if let footerMessage {
                        HStack(spacing: Spacing.gap) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(Typography.tinyLabel)
                                .foregroundStyle(ThemeColors.caution)
                            Text(footerMessage)
                                .font(Typography.tinyLabel)
                                .foregroundStyle(ThemeColors.secondaryLabel)
                        }
                        .copyable(footerMessage)
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.sectionHorizontal)
        .padding(.vertical, Spacing.section)
    }

    private var systemIndicator: StatusIndicator? {
        systemStatus?.indicator
    }

    private var statusColor: Color {
        guard let indicator = systemIndicator else { return .gray }
        return ThemeColors.statusColor(indicator)
    }

    /// Shape carrying the status color plus, for non-operational states, an
    /// inset SF Symbol so the severity is distinguishable without color.
    /// Operational and unknown stay plain dots — they're the visual default.
    @ViewBuilder
    private var statusDot: some View {
        ZStack {
            Circle()
                .fill(statusColor)
                .frame(width: Layout.dotSizeSmall, height: Layout.dotSizeSmall)
            if let symbol = statusSymbol {
                Image(systemName: symbol)
                    .font(.system(size: Layout.dotSizeSmall * 0.72, weight: .bold))
                    .foregroundStyle(Color.white)
            }
        }
        .accessibilityLabel(statusTooltip)
    }

    private var statusSymbol: String? {
        switch systemIndicator {
        case .degradedPerformance: "exclamationmark"
        case .partialOutage, .majorOutage: "xmark"
        case .maintenance: "wrench.adjustable"
        case .operational, .unknown, .none: nil
        }
    }

    static func relativeTime(_ date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 5 { return "just now" }
        if elapsed < 60 { return "\(Int(elapsed))s ago" }
        if elapsed < 3_600 { return "\(Int(elapsed / 60))m ago" }
        return "\(Int(elapsed / 3_600))h ago"
    }

    static let absoluteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .medium
        f.dateStyle = .none
        return f
    }()

    static func absoluteTime(_ date: Date) -> String {
        absoluteFormatter.string(from: date)
    }

    private var statusTooltip: String {
        switch systemIndicator {
        case .operational: "All systems operational"
        case .degradedPerformance: "Degraded performance"
        case .partialOutage: "Partial outage"
        case .majorOutage: "Major outage"
        case .maintenance: "Under maintenance"
        case .unknown, .none: "Check system status"
        }
    }
}

/// Displays "Updated Xs/Xm/Xh ago" — uses TimelineView (only renders while in view hierarchy).
/// The popover's orderOut removes the view from the hierarchy, so this naturally stops ticking.
/// When `isStale` is true, shows "Cached" prefix to indicate rate limits may be outdated
/// (e.g., when API returns 429 without rate limit headers during heavy throttling).
private struct RelativeTimeText: View {
    let date: Date
    var isStale: Bool = false
    var alternateText: String? = nil
    var alternateTooltip: String? = nil

    var body: some View {
        TimelineView(.periodic(from: .now, by: 10)) { _ in
            let resolvedAlternate: String? = alternateText.flatMap { text in
                Int(Date().timeIntervalSinceReferenceDate / 10).isMultiple(of: 2) ? text : nil
            }
            let text = resolvedAlternate
                ?? (isStale
                    ? "Cached \(PopoverFooterView.relativeTime(date))"
                    : "Updated \(PopoverFooterView.relativeTime(date))")
            Text(text)
                .font(Typography.monoTiny)
                .foregroundStyle(isStale ? ThemeColors.caution : ThemeColors.tertiaryLabel)
                .help(resolvedAlternate != nil
                    ? (alternateTooltip ?? "")
                    : (isStale
                        ? "Rate limits may be stale — API is rate-limiting probes. Last fresh: \(PopoverFooterView.absoluteTime(date))"
                        : "Last fetched: \(PopoverFooterView.absoluteTime(date))"))
        }
    }
}
