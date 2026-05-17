import SwiftUI

/// Status alerts and rate limit alerts.
struct AlertSettingsSection: View {
    @AppStorage(UserDefaultsKeys.alertStatus) private var alertStatus: Bool = false
    @AppStorage(UserDefaultsKeys.alertRateLimit) private var alertRateLimit: Bool = false
    @AppStorage(UserDefaultsKeys.rateLimitThreshold) private var rateLimitThreshold: Double = 80

    var body: some View {
        HStack(spacing: Spacing.section) {
            Text("Alerts")
                .font(Typography.caption)
                .foregroundStyle(ThemeColors.secondaryLabel)
                .frame(width: Layout.settingsLabel, alignment: .trailing)
            Toggle("Status", isOn: $alertStatus)
                .toggleStyle(.checkbox)
                .font(Typography.caption)
                .help("Notify on Claude.ai outages and incidents")
                .onChange(of: alertStatus) { on in
                    if on { NotificationManager.shared.requestPermission() }
                }
            Toggle("Rate Limit", isOn: $alertRateLimit)
                .toggleStyle(.checkbox)
                .font(Typography.caption)
                .help("Notify when usage exceeds threshold")
                .onChange(of: alertRateLimit) { on in
                    if on { NotificationManager.shared.requestPermission() }
                }
            if alertStatus {
                LinkActionButton(
                    label: "Test",
                    size: .compact,
                    help: "Send a test notification",
                    accessibilityLabel: "Test alerts",
                    action: { NotificationManager.shared.testAlerts() }
                )
            }
        }
        if alertRateLimit {
            VStack(spacing: Spacing.tight) {
                HStack(spacing: Spacing.section) {
                    Spacer().frame(width: Layout.settingsLabel)
                    Slider(value: $rateLimitThreshold, in: 50...95, step: 5)
                        .accessibilityLabel("Rate limit alert threshold")
                        .accessibilityValue("\(Int(rateLimitThreshold)) percent")
                        .help("Alert when usage exceeds \(Int(rateLimitThreshold))%")
                    Text("\(Int(rateLimitThreshold))%")
                        .font(Typography.monoCaption)
                        .frame(width: Layout.sliderValueLabel, alignment: .trailing)
                }
                sliderMarks(labels: ["50%", "60%", "70%", "80%", "90%", "95%"], leadingPad: Layout.settingsLabel)
            }
        }
    }
}
