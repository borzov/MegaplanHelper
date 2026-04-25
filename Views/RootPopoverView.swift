import AppKit
import SwiftUI

/// Top-level popover container. Hosts the shared header (greeting + tab picker),
/// switches between authenticated tabs, and renders the global footer.
struct RootPopoverView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var notificationListViewModel: NotificationListViewModel
    @EnvironmentObject private var taskListViewModel: TaskListViewModel
    @EnvironmentObject private var settingsViewModel: SettingsViewModel

    @State private var selectedTab: AppTab = .notifications

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if appState.isAuthenticated {
                PopoverHeaderView(
                    selectedTab: $selectedTab,
                    firstName: appState.firstName,
                    unreadCount: appState.unreadCount,
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
        .alert(item: $appState.alertItem) { alert in
            Alert(
                title: Text("error.title"),
                message: Text(alert.message),
                dismissButton: .default(Text("general.ok"))
            )
        }
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
                SettingsWindowManager.shared.showSettings(appState: appState, settingsViewModel: settingsViewModel)
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

