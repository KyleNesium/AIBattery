import SwiftUI

/// Status alerts + rate limit alerts.
struct AlertSettingsSection: View {
    @AppStorage(UserDefaultsKeys.alertStatus) private var alertStatus: Bool = false
    @AppStorage(UserDefaultsKeys.alertRateLimit) private var alertRateLimit: Bool = false
    @AppStorage(UserDefaultsKeys.rateLimitThreshold) private var rateLimitThreshold: Double = 80

    var body: some View {
        HStack(spacing: 8) {
            Text("Alerts")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
            Toggle("Status", isOn: $alertStatus)
                .toggleStyle(.checkbox)
                .font(.caption)
                .onChange(of: alertStatus) { on in
                    if on { NotificationManager.shared.requestPermission() }
                }
            Toggle("Rate Limit", isOn: $alertRateLimit)
                .toggleStyle(.checkbox)
                .font(.caption)
                .onChange(of: alertRateLimit) { on in
                    if on { NotificationManager.shared.requestPermission() }
                }
            if alertStatus {
                Button("Test") {
                    NotificationManager.shared.testAlerts()
                }
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundStyle(.blue)
            }
        }
        if alertRateLimit {
            VStack(spacing: 2) {
                HStack(spacing: 8) {
                    Spacer().frame(width: 50)
                    Slider(value: $rateLimitThreshold, in: 50...95, step: 5)
                        .accessibilityLabel("Rate limit alert threshold")
                        .accessibilityValue("\(Int(rateLimitThreshold)) percent")
                    Text("\(Int(rateLimitThreshold))%")
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 28, alignment: .trailing)
                }
                sliderMarks(labels: ["50%", "60%", "70%", "80%", "90%", "95%"], leadingPad: 50)
            }
        }
    }
}
