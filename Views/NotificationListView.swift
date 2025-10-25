import AppKit
import SwiftUI

struct NotificationListView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var showingSettings: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if appState.isAuthenticated {
                content
            } else {
                AuthView()
            }
            
            Spacer()
            
            if appState.isAuthenticated {
                bottomButtons
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .alert(item: $appState.alertItem) { alert in
            Alert(
                title: Text("error.title"),
                message: Text(alert.message),
                dismissButton: .default(Text("general.ok"))
            )
        }
        .onAppear {
            if appState.isAuthenticated {
                appState.refreshNow()
            }
        }
        .onChange(of: showingSettings) { newValue in
            if newValue {
                SettingsWindowManager.shared.showSettings(appState: appState)
                // Reset the binding after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    showingSettings = false
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if appState.isAuthenticated {
                HStack {
                    Text("notifications.title")
                        .font(.headline)
                    
                    Spacer()
                    
                    Button {
                        appState.refreshNow()
                    } label: {
                        if appState.isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("notifications.refresh"))
                }
                
                // Персональное приветствие
                if !appState.firstName.isEmpty {
                    Text("\(appState.firstName), у вас \(appState.unreadCount) непрочитанных уведомлений:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                HStack {
                    Text("notifications.title")
                        .font(.headline)
                    
                    Spacer()
                }
            }
        }
    }
    
    private var bottomButtons: some View {
        HStack(spacing: 14) {
            // Кнопка API логов только для администратора
            if appState.username == "borzov@ruvents.com" {
                Button {
                    let logContent = APILogger.getLogContent()
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(logContent, forType: .string)
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .foregroundColor(.blue)
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Copy API Log"))
                
                // Кнопки быстрого доступа
                Button {
                    if let url = URL(string: "https://\(appState.domain)/knowledge/") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "book.closed")
                        .foregroundColor(.green)
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Knowledge Base"))
                
                Button {
                    if let url = URL(string: "https://\(appState.domain)/deals/list/") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "briefcase")
                        .foregroundColor(.orange)
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Deals"))
                
                Button {
                    if let url = URL(string: "https://\(appState.domain)/task/") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "checklist")
                        .foregroundColor(.purple)
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Tasks"))
            }
            
            Spacer()
            
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .foregroundColor(.gray)
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Settings"))
            
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .foregroundColor(.red)
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Quit Application"))
        }
        .padding(.vertical, 0)
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var content: some View {
        if appState.notifications.isEmpty {
            if appState.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("notifications.loading")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                Text("notifications.empty")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .foregroundColor(.secondary)
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(appState.notifications) { notification in
                        NotificationRow(notification: notification, onMarkRead: {
                            appState.markNotificationAsRead(notification)
                        })
                        .transition(.opacity.combined(with: .scale))
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct NotificationRow: View {
    let notification: MegaplanNotification
    let onMarkRead: () -> Void
    @State private var isMarkingAsRead = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: notification.notificationIcon)
                                    .foregroundColor(.blue)
                                    .font(.caption)
                                    .frame(width: 16, height: 16)
                                
                                Text(notification.displayDate)
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                
                                Spacer()
                                
                                if notification.isMention {
                                    Image(systemName: "at")
                                        .foregroundColor(.orange)
                                        .font(.caption)
                                }
                                
                            }
                        }
                    }
                    
                    Text(notification.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(notification.body)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
                Spacer(minLength: 12)
            }

            HStack(spacing: 12) {
                if notification.size > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.right.fill")
                            .font(.caption2)
                        Text("\(notification.size) \(notification.size.pluralized((one: "комментарий", few: "комментария", many: "комментариев")))")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.gray)
                    .clipShape(Capsule())
                }
                
                Spacer()
                
                Button {
                    onMarkRead()
                } label: {
                    HStack(spacing: 4) {
                        if isMarkingAsRead {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.green)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                    }
                    .foregroundColor(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.green.opacity(0.15))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isMarkingAsRead)
                .accessibilityLabel(Text("notifications.markRead"))
            }



        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(notification.isMention ? Color.orange.opacity(0.05) : Color(.windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if let link = notification.link {
                NSWorkspace.shared.open(link)
            }
        }
        .onChange(of: notification.isRead) { _ in
            isMarkingAsRead = false
        }
    }
}

#if DEBUG
struct NotificationListView_Previews: PreviewProvider {
    static var previews: some View {
        NotificationListView(showingSettings: .constant(false))
            .environmentObject({
                let state = AppState()
                state.notifications = [
                    .previewSample
                ]
                state.isAuthenticated = true
                return state
            }())
            .frame(width: 360, height: 420)
    }
}
#endif
