import SwiftUI

@main
struct MegaplanMenuBarApp: App {
    @StateObject private var appState = AppState()
    @State private var showingSettings = false

    init() {
        AppLogger.info("MegaplanMenuBarApp initializing...")
    }

    var body: some Scene {
        MenuBarExtra(
            content: {
                NotificationListView(showingSettings: $showingSettings)
                    .environmentObject(appState)
                    .frame(minWidth: 340, minHeight: 550)
            },
            label: {
                MenuBarIconView(unreadCount: appState.unreadCount, showingSettings: $showingSettings)
                    .environmentObject(appState)
            }
        )
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .frame(width: 480, height: 500)
        }
    }
}

private struct MenuBarIconView: View {
    let unreadCount: Int
    @EnvironmentObject var appState: AppState
    @Binding var showingSettings: Bool
    @State private var menuBarImage: NSImage?
    
    private static var cachedMenuBarImage: NSImage?

    var body: some View {
        Group {
            if let image = menuBarImage {
                Image(nsImage: image)
                    .renderingMode(.original)
            } else {
                Image(systemName: "bell.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 14))
            }
        }
        .onAppear {
            if menuBarImage == nil {
                resizeMenuBarIcon()
            }
        }
        .overlay(alignment: .topTrailing) {
                if unreadCount > 0 {
                    Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(Color.red)
                        )
                        .offset(x: 6, y: -6)
                }
            }
            .accessibilityLabel(Text("menu.title"))
            .accessibilityValue(Text("\(unreadCount)"))
            .contextMenu {
                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                
                if appState.isAuthenticated {
                    Button {
                        Task {
                            await appState.logout()
                        }
                    } label: {
                        Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
    }
    
    private func resizeMenuBarIcon() {
        // Check cache first
        if let cached = Self.cachedMenuBarImage {
            menuBarImage = cached
            return
        }
        
        guard let nsImage = NSImage(named: "MenuBarIcon") else {
            return
        }
        
        // Resize on background thread to avoid blocking main thread
        Task.detached(priority: .userInitiated) {
            // Create resized image using bitmap representation
            let targetSize = NSSize(width: 18, height: 18)
            let resizedImage = NSImage(size: targetSize)
            
            resizedImage.lockFocus()
            nsImage.size = targetSize
            nsImage.draw(at: .zero, from: .zero, operation: .copy, fraction: 1.0)
            resizedImage.unlockFocus()
            
            await MainActor.run {
                Self.cachedMenuBarImage = resizedImage
                menuBarImage = resizedImage
            }
        }
    }
}
