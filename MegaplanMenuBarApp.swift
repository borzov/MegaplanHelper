import SwiftUI

@main
struct MegaplanMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState: AppState
    @StateObject private var notificationListViewModel: NotificationListViewModel
    @StateObject private var settingsViewModel: SettingsViewModel

    init() {
        AppLogger.info("MegaplanMenuBarApp initializing...")
        let appState = AppState()
        _appState = StateObject(wrappedValue: appState)
        _notificationListViewModel = StateObject(wrappedValue: NotificationListViewModel(appState: appState))
        _settingsViewModel = StateObject(wrappedValue: SettingsViewModel(appState: appState))
    }

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(settingsViewModel)
                .frame(width: 480, height: 500)
        }
    }
}

/// App delegate to manage the status bar controller lifecycle.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var appState: AppState?
    private var notificationListViewModel: NotificationListViewModel?
    private var settingsViewModel: SettingsViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.info("AppDelegate: applicationDidFinishLaunching")

        // Create shared state objects
        let appState = AppState()
        let notificationListViewModel = NotificationListViewModel(appState: appState)
        let settingsViewModel = SettingsViewModel(appState: appState)

        self.appState = appState
        self.notificationListViewModel = notificationListViewModel
        self.settingsViewModel = settingsViewModel

        // Create content view for popover
        let contentView = NotificationListView()
            .environmentObject(appState)
            .environmentObject(notificationListViewModel)
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
        settingsViewModel = nil
        notificationListViewModel = nil
        appState = nil
    }
}
