import AppKit
import SwiftUI

enum AppearanceTheme {
    static func colorScheme(for rawValue: String) -> ColorScheme? {
        switch rawValue {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return nil
        }
    }
}

struct PopoverFontMetrics: Equatable {
    let iconSmall: CGFloat
    let iconMedium: CGFloat
    let iconLarge: CGFloat
    let sectionHeader: CGFloat
    let toastPrimary: CGFloat
    let toastSecondary: CGFloat
    let title: CGFloat
    let body: CGFloat
    let subBody: CGFloat
    let badge: CGFloat

    static func resolve(_ rawValue: String) -> PopoverFontMetrics {
        switch rawValue {
        case "small":
            return .init(
                iconSmall: 11,
                iconMedium: 12,
                iconLarge: 34,
                sectionHeader: 11,
                toastPrimary: 12,
                toastSecondary: 11,
                title: 14,
                body: 12,
                subBody: 10,
                badge: 11
            )
        case "large":
            return .init(
                iconSmall: 13,
                iconMedium: 16,
                iconLarge: 40,
                sectionHeader: 13,
                toastPrimary: 14,
                toastSecondary: 13,
                title: 17,
                body: 14,
                subBody: 12,
                badge: 13
            )
        default:
            return .init(
                iconSmall: 12,
                iconMedium: 14,
                iconLarge: 36,
                sectionHeader: 12,
                toastPrimary: 13,
                toastSecondary: 12,
                title: 15,
                body: 13,
                subBody: 11,
                badge: 12
            )
        }
    }
}

private struct PopoverFontMetricsKey: EnvironmentKey {
    static let defaultValue = PopoverFontMetrics.resolve("medium")
}

extension EnvironmentValues {
    var popoverFontMetrics: PopoverFontMetrics {
        get { self[PopoverFontMetricsKey.self] }
        set { self[PopoverFontMetricsKey.self] = newValue }
    }
}

/// Top-level popover container. Hosts the shared header (greeting + tab picker),
/// switches between authenticated tabs, and renders the global footer.
struct RootPopoverView: View {
    @Environment(\.popoverFontMetrics) private var metrics
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var notificationListViewModel: NotificationListViewModel
    @EnvironmentObject private var taskListViewModel: TaskListViewModel
    @AppStorage("appTheme") private var appTheme: String = "system"
    @AppStorage("fontSize") private var fontSize: String = "medium"

    @State private var selectedTab: AppTab = .notifications
    @State private var isHotkeysRegistered = false

    var body: some View {
        Group {
            if appState.isAuthenticated {
                authenticatedContent
            } else {
                AuthView()
            }
        }
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
        .onAppear {
            registerHotkeyHandlersIfNeeded()
        }
        .preferredColorScheme(AppearanceTheme.colorScheme(for: appTheme))
        .environment(\.popoverFontMetrics, PopoverFontMetrics.resolve(fontSize))
        .id(appTheme)
    }

    private var authenticatedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            PopoverHeaderView(
                selectedTab: $selectedTab,
                firstName: appState.firstName,
                unreadCount: appState.unreadCount,
                tasksUnreadCount: appState.tasksUnreadCount,
                isLoading: appState.isLoading || appState.isTasksLoading,
                isSearchActive: activeTabIsSearchActive,
                isFilterActive: taskListViewModel.isFilterPanelActive,
                showsFilterButton: selectedTab == .tasks,
                onRefresh: { appState.refreshNow() },
                onToggleSearch: toggleActiveTabSearch,
                onToggleFilter: toggleTasksFilter
            )
            .frame(maxWidth: .infinity)

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
        }
        .padding(16)
        .frame(minWidth: 340, maxWidth: 400, minHeight: 600, maxHeight: 1000, alignment: .top)
    }

    private var activeTabIsSearchActive: Bool {
        switch selectedTab {
        case .notifications: return notificationListViewModel.isSearchActive
        case .tasks: return taskListViewModel.isSearchActive
        }
    }

    private func toggleActiveTabSearch() {
        withAnimation {
            switch selectedTab {
            case .notifications:
                notificationListViewModel.isSearchActive.toggle()
                if !notificationListViewModel.isSearchActive {
                    notificationListViewModel.clearSearch()
                }
            case .tasks:
                taskListViewModel.toggleSearch()
            }
        }
    }

    private func toggleTasksFilter() {
        withAnimation { taskListViewModel.isFilterPanelActive.toggle() }
    }

    private func registerHotkeyHandlersIfNeeded() {
        guard !isHotkeysRegistered else { return }
        isHotkeysRegistered = true

        let manager = HotkeyManager.shared
        manager.register(.openPopover) {
            // Reserved for global popover open behavior.
        }
        manager.register(.refreshNow) {
            appState.refreshNow()
        }
        manager.register(.focusSearch) {
            toggleActiveTabSearch()
        }
        manager.register(.markAllRead) {
            markAllNotificationsAsReadForActiveTab()
        }
    }

    private func markAllNotificationsAsReadForActiveTab() {
        guard selectedTab == .notifications else { return }
        for notification in notificationListViewModel.notifications where !notification.isRead {
            appState.markNotificationAsRead(notification)
        }
    }

    @ViewBuilder
    private var transientToast: some View {
        if let message = appState.transientToast {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: metrics.toastPrimary, weight: .semibold))
                    .foregroundColor(.white)
                Text(message)
                    .font(.system(size: metrics.toastSecondary, weight: .medium))
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
                        .font(.system(size: metrics.iconMedium))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Copy API Log"))

                Button {
                    if let url = URL(string: "https://\(appState.domain)/knowledge/") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "book.closed")
                        .font(.system(size: metrics.iconMedium))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Knowledge Base"))

                Button {
                    if let url = URL(string: "https://\(appState.domain)/deals/list/") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "briefcase")
                        .font(.system(size: metrics.iconMedium))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Deals"))

                Button {
                    if let url = URL(string: "https://\(appState.domain)/task/") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "checklist")
                        .font(.system(size: metrics.iconMedium))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Tasks"))
            }

            Spacer()

            Button {
                openAppSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: metrics.iconMedium))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Settings"))

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: metrics.iconMedium))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Quit Application"))
        }
        .padding(.vertical, 0)
        .padding(.horizontal, 4)
    }
}

