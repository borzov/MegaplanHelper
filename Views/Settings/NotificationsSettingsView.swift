import SwiftUI
import UserNotifications
import AppKit

struct NotificationsSettingsView: View {
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = true
    @AppStorage("groupingEnabled") private var groupingEnabled: Bool = true
    @State private var lastTestStatus: TestStatus?

    private enum TestStatus: Equatable {
        case sent
        case denied
        case notAllowed       // UNError code 1 — system-level rejection
        case otherError(String)

        var message: String {
            switch self {
            case .sent: return String(localized: "settings.notifications.testSent")
            case .denied: return String(localized: "settings.notifications.testDenied")
            case .notAllowed: return String(localized: "settings.notifications.testNotAllowed")
            case .otherError(let m): return m
            }
        }

        var requiresSystemSettings: Bool {
            self == .denied || self == .notAllowed
        }
    }

    var body: some View {
        Form {
            Section(String(localized: "settings.notifications.section")) {
                Toggle(String(localized: "settings.notifications.enabled"), isOn: $notificationsEnabled)
                Toggle(String(localized: "settings.notifications.grouping"), isOn: $groupingEnabled)
                    .disabled(!notificationsEnabled)
            }
            Section {
                Button(String(localized: "settings.notifications.test")) {
                    Task { await sendTest() }
                }
                .disabled(!notificationsEnabled)

                if let status = lastTestStatus {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: status == .sent ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(status == .sent ? .green : .orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(status.message)
                                .font(.callout)
                            if status.requiresSystemSettings {
                                Button(String(localized: "settings.notifications.openSystemSettings")) {
                                    openNotificationSystemSettings()
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(.vertical, 2)
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
                lastTestStatus = .denied
                return
            }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "settings.notifications.testTitle")
            content.body = String(localized: "settings.notifications.testBody")
            let req = UNNotificationRequest(identifier: "test-\(UUID().uuidString)",
                                            content: content,
                                            trigger: nil)
            try await center.add(req)
            lastTestStatus = .sent
        } catch let error as NSError where error.domain == "UNErrorDomain" && error.code == 1 {
            // UNErrorCodeNotificationsNotAllowed
            lastTestStatus = .notAllowed
        } catch {
            lastTestStatus = .otherError(error.localizedDescription)
        }
    }

    private func openNotificationSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
        NSWorkspace.shared.open(url)
    }
}
