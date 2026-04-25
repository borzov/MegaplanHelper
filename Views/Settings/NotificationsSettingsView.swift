import SwiftUI
import UserNotifications

struct NotificationsSettingsView: View {
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = true
    @AppStorage("groupingEnabled") private var groupingEnabled: Bool = true
    @State private var lastTestStatus: String?

    var body: some View {
        Form {
            Section(String(localized: "settings.notifications.section")) {
                Toggle(String(localized: "settings.notifications.enabled"), isOn: $notificationsEnabled)
                Toggle(String(localized: "settings.notifications.grouping"), isOn: $groupingEnabled)
                    .disabled(!notificationsEnabled)
            }
            Section {
                HStack {
                    Button(String(localized: "settings.notifications.test")) {
                        Task { await sendTest() }
                    }
                    .disabled(!notificationsEnabled)
                    if let lastTestStatus {
                        Text(lastTestStatus).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func sendTest() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            guard granted else {
                lastTestStatus = String(localized: "settings.notifications.testDenied")
                return
            }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "settings.notifications.testTitle")
            content.body = String(localized: "settings.notifications.testBody")
            let req = UNNotificationRequest(identifier: "test-\(UUID().uuidString)",
                                            content: content,
                                            trigger: nil)
            try await center.add(req)
            lastTestStatus = String(localized: "settings.notifications.testSent")
        } catch {
            lastTestStatus = error.localizedDescription
        }
    }
}
