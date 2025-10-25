import SwiftUI
import AppKit

class SettingsWindowManager: ObservableObject {
    static let shared = SettingsWindowManager()
    private var settingsWindow: NSWindow?
    
    private init() {}
    
    func showSettings(appState: AppState) {
        // If window already exists, bring it to front
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let settingsView = SettingsView()
            .environmentObject(appState)
            .frame(width: 480, height: 500)
        
        let hostingController = NSHostingController(rootView: settingsView)
        
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Настройки"
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
        
        // Handle window close to clean up
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.settingsWindow = nil
        }
        
        self.settingsWindow = window
        
        // Hide menu bar window
        if let menuBarWindow = NSApp.windows.first(where: { $0.title.isEmpty }) {
            menuBarWindow.orderOut(nil)
        }
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func closeSettings() {
        settingsWindow?.close()
        settingsWindow = nil
    }
}

