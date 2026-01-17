import SwiftUI
import AppKit

class SettingsWindowManager: ObservableObject {
    static let shared = SettingsWindowManager()
    private var settingsWindow: NSWindow?
    private var windowObserver: NSObjectProtocol?
    
    private init() {}
    
    func showSettings(appState: AppState, settingsViewModel: SettingsViewModel) {
        AppLogger.info("showSettings called")
        
        // If window already exists, bring it to front
        if let window = settingsWindow {
            AppLogger.info("Settings window already exists, bringing to front")
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        AppLogger.info("Creating new settings window")
        
        let settingsView = SettingsView()
            .environmentObject(appState)
            .environmentObject(settingsViewModel)
            .frame(width: 480, height: 500)
        
        let hostingController = NSHostingController(rootView: settingsView)
        
        let window = NSWindow(contentViewController: hostingController)
        window.title = String(localized: "settings.title")
        window.styleMask = [.titled, .closable]
        window.level = .normal
        window.isReleasedWhenClosed = false
        
        // Set window size first
        window.setContentSize(NSSize(width: 480, height: 500))
        
        // Center window on screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowSize = NSSize(width: 480, height: 500)
            let x = (screenFrame.width - windowSize.width) / 2 + screenFrame.origin.x
            let y = (screenFrame.height - windowSize.height) / 2 + screenFrame.origin.y
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        // Обработка закрытия окна для очистки ресурсов
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.cleanup()
        }
        
        self.settingsWindow = window
        
        // Скрытие popover окна menu bar (определяется по statusItem уровню)
        if let menuBarWindow = NSApp.windows.first(where: { $0.level == .statusBar || $0.level == .popUpMenu }) {
            menuBarWindow.orderOut(nil)
        }
        
        // Activate app first, then show window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        
        AppLogger.info("Settings window created and shown")
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

