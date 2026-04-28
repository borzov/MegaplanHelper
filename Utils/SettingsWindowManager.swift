import SwiftUI
import AppKit

@MainActor
final class SettingsWindowManager {
    static let shared = SettingsWindowManager()

    private var settingsWindow: NSWindow?
    private var windowObserver: (any NSObjectProtocol)?

    private enum WindowConstants {
        static let width: CGFloat = 760
        static let height: CGFloat = 560
        static let minWidth: CGFloat = 720
        static let minHeight: CGFloat = 520
        static let autosaveName = "MegaplanSettings"
    }

    private init() {}

    func showSettings(appState: AppState, notificationListViewModel: NotificationListViewModel) {
        if let window = settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        AppLogger.info("Opening Settings window")

        let settingsView = SettingsView()
            .environmentObject(appState)
            .environmentObject(notificationListViewModel)

        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = String(localized: "settings.title")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.level = .normal
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: WindowConstants.minWidth, height: WindowConstants.minHeight)
        window.setContentSize(NSSize(width: WindowConstants.width, height: WindowConstants.height))

        // Restore previous size and position from autosave; fall back to centered.
        let restoredFromAutosave = window.setFrameUsingName(WindowConstants.autosaveName)
        window.setFrameAutosaveName(WindowConstants.autosaveName)
        if !restoredFromAutosave, let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowSize = NSSize(width: WindowConstants.width, height: WindowConstants.height)
            let x = (screenFrame.width - windowSize.width) / 2 + screenFrame.origin.x
            let y = (screenFrame.height - windowSize.height) / 2 + screenFrame.origin.y
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.cleanup() }
        }

        self.settingsWindow = window

        // Явно закрываем popover статус-бара перед показом настроек.
        StatusBarController.current?.hidePopover()

        // Активируем приложение, не меняя activation policy: остаёмся `.accessory`,
        // чтобы иконка в Dock/Cmd+Tab не появлялась.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func closeSettings() {
        settingsWindow?.close()
        cleanup()
    }

    private func cleanup() {
        if let observer = windowObserver {
            NotificationCenter.default.removeObserver(observer)
            windowObserver = nil
        }
        settingsWindow = nil
    }
}
