import SwiftUI

@main
struct MegaplanMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.appState)
                .environmentObject(appDelegate.settingsViewModel)
                .frame(width: 480, height: 500)
        }
    }
}

/// App delegate to manage the status bar controller lifecycle.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    let appState: AppState
    let notificationListViewModel: NotificationListViewModel
    let taskListViewModel: TaskListViewModel
    let settingsViewModel: SettingsViewModel

    @MainActor
    override init() {
        AppLogger.info("AppDelegate: Initializing shared state objects")

        // Create shared state objects once
        self.appState = AppState()
        self.notificationListViewModel = NotificationListViewModel(appState: self.appState)
        self.taskListViewModel = TaskListViewModel(appState: self.appState)
        self.settingsViewModel = SettingsViewModel(appState: self.appState)

        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.info("AppDelegate: applicationDidFinishLaunching")

        // Create content view for popover — RootPopoverView hosts both tabs.
        let contentView = RootPopoverView()
            .environmentObject(appState)
            .environmentObject(notificationListViewModel)
            .environmentObject(taskListViewModel)
            .environmentObject(settingsViewModel)
            .frame(minWidth: 340, maxWidth: 400, minHeight: 600, maxHeight: 1000)

        // Setup status bar controller
        let controller = StatusBarController()
        controller.setup(
            appState: appState,
            settingsViewModel: settingsViewModel,
            contentView: contentView
        )
        self.statusBarController = controller

        AppLogger.info("AppDelegate: Status bar setup complete")
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLogger.info("AppDelegate: applicationWillTerminate")
        cleanup()
    }

    private func cleanup() {
        statusBarController = nil
        // State objects are let constants and will be deallocated when AppDelegate is deallocated
    }
}
