import SwiftUI

@main
struct MegaplanMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            // Empty placeholder. The real Settings window is owned by
            // `SettingsWindowManager` so that the menu bar app can stay
            // `.accessory` and the popover/UX remains AppKit-driven.
            EmptyView()
        }
    }
}

/// App delegate manages the status bar controller lifecycle and shared state.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    let appState: AppState
    let notificationListViewModel: NotificationListViewModel
    let taskListViewModel: TaskListViewModel

    @MainActor
    override init() {
        AppLogger.info("AppDelegate: Initializing shared state objects")
        self.appState = AppState()
        self.notificationListViewModel = NotificationListViewModel(appState: self.appState)
        self.taskListViewModel = TaskListViewModel(appState: self.appState)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.info("AppDelegate: applicationDidFinishLaunching")

        let contentView = RootPopoverView()
            .environmentObject(appState)
            .environmentObject(notificationListViewModel)
            .environmentObject(taskListViewModel)
            .frame(minWidth: 340, maxWidth: 400, minHeight: 600, maxHeight: 1000)

        let controller = StatusBarController()
        controller.setup(
            appState: appState,
            notificationListViewModel: notificationListViewModel,
            contentView: contentView
        )
        self.statusBarController = controller

        AppLogger.info("AppDelegate: Status bar setup complete")
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLogger.info("AppDelegate: applicationWillTerminate")
        statusBarController = nil
    }
}
