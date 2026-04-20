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
    @State private var logoutHovered = false
    @State private var quitHovered = false

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
                    Circle()
                        .fill(statusColor)
                        .frame(width: Layout.dotSizeSmall, height: Layout.dotSizeSmall)
                        .accessibilityLabel(statusTooltip)
                }

                Spacer()

                // Logout (active account) — two-tap confirmation
                Button(action: {
                    if showLogoutConfirm {
                        onLogout()
                    } else {
                        onRequestLogout()
                    }
                }) {
                    HStack(spacing: Spacing.tight) {
                        Image(systemName: showLogoutConfirm ? "exclamationmark.triangle" : "rectangle.portrait.and.arrow.right")
                            .font(Typography.monoTiny)
                        Text(showLogoutConfirm ? "Confirm?" : "Logout")
                            .font(Typography.tinyLabel)
                            .underline(logoutHovered)
                    }
                    .fixedSize()
                }
                .buttonStyle(.plain)
                .foregroundStyle(showLogoutConfirm ? ThemeColors.danger : .secondary)
                .onHover { logoutHovered = $0 }
                .animation(MotionConstants.snappy, value: showLogoutConfirm)
                .accessibilityLabel(showLogoutConfirm ? "Confirm logout" : "Logout")
                .accessibilityHint("Sign out of active Claude account")

                // Quit
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    HStack(spacing: Spacing.tight) {
                        Image(systemName: "xmark.circle")
                            .font(Typography.monoTiny)
                        Text("Quit")
                            .font(Typography.tinyLabel)
                            .underline(quitHovered)
                    }
                    .fixedSize()
                }
                .buttonStyle(.plain)
                .foregroundStyle(ThemeColors.secondaryLabel)
                .onHover { quitHovered = $0 }
                .help("Quit (⌘Q)")
                .accessibilityLabel("Quit AI Battery")
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

    static func relativeTime(_ date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 5 { return "just now" }
        if elapsed < 60 { return "\(Int(elapsed))s ago" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))m ago" }
        return "\(Int(elapsed / 3600))h ago"
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
        case .operational: return "All systems operational"
        case .degradedPerformance: return "Degraded performance"
        case .partialOutage: return "Partial outage"
        case .majorOutage: return "Major outage"
        case .maintenance: return "Under maintenance"
        case .unknown, .none: return "Check system status"
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
