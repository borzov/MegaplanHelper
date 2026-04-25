import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case notifications
    case tasks

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .notifications: return String(localized: "tabs.notifications")
        case .tasks: return String(localized: "tabs.tasks")
        }
    }
}

struct PopoverHeaderView: View {
    @Binding var selectedTab: AppTab
    let firstName: String
    let unreadCount: Int
    let tasksUnreadCount: Int
    let isLoading: Bool
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                if !firstName.isEmpty {
                    Text(String(format: String(localized: "popover.greeting"), firstName))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    Text("menu.title")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }

                Spacer()

                Button(action: onRefresh) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 18, height: 18)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .medium))
                    }
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("notifications.refresh"))
            }

            Picker("", selection: $selectedTab) {
                Text(notificationsLabel).tag(AppTab.notifications)
                Text(tasksLabel).tag(AppTab.tasks)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var notificationsLabel: String {
        if unreadCount > 0 {
            return "\(AppTab.notifications.displayName) · \(unreadCount)"
        }
        return AppTab.notifications.displayName
    }

    private var tasksLabel: String {
        if tasksUnreadCount > 0 {
            return "\(AppTab.tasks.displayName) · \(tasksUnreadCount)"
        }
        return AppTab.tasks.displayName
    }
}

#if DEBUG
struct PopoverHeaderView_Previews: PreviewProvider {
    @State static var tab: AppTab = .notifications
    static var previews: some View {
        PopoverHeaderView(
            selectedTab: .constant(.notifications),
            firstName: "Максим",
            unreadCount: 12,
            tasksUnreadCount: 7,
            isLoading: false,
            onRefresh: {}
        )
        .padding()
        .frame(width: 370)
    }
}
#endif
