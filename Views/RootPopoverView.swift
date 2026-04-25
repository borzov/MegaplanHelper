import AppKit
import SwiftUI

/// Top-level popover container. Hosts the shared header (greeting + tab picker),
/// switches between authenticated tabs, and renders the global footer.
struct RootPopoverView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var notificationListViewModel: NotificationListViewModel
    @EnvironmentObject private var taskListViewModel: TaskListViewModel

    @State private var selectedTab: AppTab = .notifications

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if appState.isAuthenticated {
                PopoverHeaderView(
                    selectedTab: $selectedTab,
                    firstName: appState.firstName,
                    unreadCount: appState.unreadCount,
                    tasksUnreadCount: appState.tasksUnreadCount,
                    isLoading: appState.isLoading || appState.isTasksLoading,
                    onRefresh: { appState.refreshNow() }
                )

                Group {
                    switch selectedTab {
                    case .notifications:
                        NotificationListView()
                    case .tasks:
                        TaskListView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                footerButtons
            } else {
                HStack {
                    Text("notifications.title")
                        .font(.headline)
                    Spacer()
                }
                AuthView()
                Spacer()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            transientToast
                .padding(.bottom, 12)
        }
        .alert(item: $appState.alertItem) { alert in
            Alert(
                title: Text("error.title"),
                message: Text(alert.message),
                dismissButton: .default(Text("general.ok"))
            )
        }
    }

    @ViewBuilder
    private var transientToast: some View {
        if let message = appState.transientToast {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.82))
                    .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.32, dampingFraction: 0.85), value: appState.transientToast)
        }
    }

    private func openAppSettings() {
        SettingsWindowManager.shared.showSettings(
            appState: appState,
            notificationListViewModel: notificationListViewModel
        )
    }

    private var footerButtons: some View {
        HStack(spacing: 14) {
            if appState.isAdmin {
                Button {
                    let logContent = APILogger.getLogContent()
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(logContent, forType: .string)
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Copy API Log"))

                Button {
                    if let url = URL(string: "https://\(appState.domain)/knowledge/") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "book.closed")
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
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Tasks"))
            }

            Spacer()

            Button {
                openAppSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Settings"))

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Quit Application"))
        }
        .padding(.vertical, 0)
        .padding(.horizontal, 4)
    }
}

