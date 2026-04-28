import SwiftUI
import AppKit
import Combine

/// Controls the menu bar status item, popover, and context menu.
@MainActor
final class StatusBarController: NSObject, ObservableObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    /// Weak singleton reference for SwiftUI views that need to drive popover sizing without explicit injection.
    static weak var current: StatusBarController?
    private var eventMonitor: Any?
    private weak var appState: AppState?
    private weak var notificationListViewModel: NotificationListViewModel?
    private var cancellables = Set<AnyCancellable>()
    private var wakeObserver: (any NSObjectProtocol)?
    private var screenChangeObserver: (any NSObjectProtocol)?
    private var isPresentingAlert = false

    nonisolated(unsafe) private static var cachedMenuBarImage: NSImage?

    override init() {
        super.init()
        Self.current = self
    }

    /// Sets up the status bar item with the given app state and content view.
    /// - Parameters:
    ///   - appState: The app state to observe for changes
    ///   - notificationListViewModel: View model passed into the Settings window
    ///   - contentView: The SwiftUI view to display in the popover
    func setup<Content: View>(
        appState: AppState,
        notificationListViewModel: NotificationListViewModel,
        contentView: Content
    ) {
        self.appState = appState
        self.notificationListViewModel = notificationListViewModel

        setupStatusItem()
        setupPopover(with: contentView)
        setupEventMonitor()
        setupSystemObservers()
        observeAppState()

        AppLogger.info("StatusBarController setup complete")
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem?.button else {
            AppLogger.error("Failed to create status bar button")
            return
        }

        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        updateIcon()
        updateBadge(appState?.unreadCount ?? 0)
    }

    private func setupPopover<Content: View>(with contentView: Content) {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 370, height: 700)
        popover.behavior = .transient
        popover.animates = true

        // Pre-warm the SwiftUI host so the first show is fully painted instead of
        // briefly showing the translucent/uninitialized NSPopover background.
        let hosting = NSHostingController(rootView: contentView)
        hosting.view.frame = NSRect(origin: .zero, size: popover.contentSize)
        hosting.view.layoutSubtreeIfNeeded()
        popover.contentViewController = hosting

        self.popover = popover
    }

    private func setupEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if self?.popover?.isShown == true {
                self?.hidePopover()
            }
        }
    }

    private func observeAppState() {
        guard let appState = appState else { return }

        appState.$unreadCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                self?.updateBadge(count)
            }
            .store(in: &cancellables)

        appState.$isOffline
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateIcon()
            }
            .store(in: &cancellables)

        appState.$alertItem
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] alert in
                self?.presentAppKitAlert(alert)
            }
            .store(in: &cancellables)
    }

    private func setupSystemObservers() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.repositionVisiblePopover()
        }

        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.repositionVisiblePopover()
        }
    }

    // MARK: - Icon and Badge

    private func updateIcon() {
        guard let button = statusItem?.button else { return }

        let image: NSImage
        if let cached = Self.cachedMenuBarImage {
            image = cached
        } else if let nsImage = NSImage(named: "MenuBarIcon") {
            // Render the 18x18 icon onto a wider canvas so the unread badge has
            // room on the right without clipping at the menu bar edge.
            let iconSize = NSSize(width: 18, height: 18)
            let canvasSize = NSSize(width: 26, height: 18)
            let resizedImage = NSImage(size: canvasSize)
            resizedImage.lockFocus()
            nsImage.size = iconSize
            nsImage.draw(at: NSPoint(x: 0, y: 0), from: .zero, operation: .copy, fraction: 1.0)
            resizedImage.unlockFocus()
            resizedImage.isTemplate = true
            Self.cachedMenuBarImage = resizedImage
            image = resizedImage
        } else {
            image = NSImage(systemSymbolName: "bell.fill", accessibilityDescription: "Notifications")
                ?? NSImage()
            image.isTemplate = true
        }

        button.image = image
        button.alphaValue = appState?.isOffline == true ? 0.5 : 1.0
    }

    private func updateBadge(_ count: Int) {
        guard let button = statusItem?.button else { return }

        // Remove existing badge subview
        button.subviews.forEach { $0.removeFromSuperview() }

        guard count > 0 else { return }

        let badgeText = count > 99 ? "99+" : "\(count)"
        let badgeView = BadgeView(text: badgeText)
        badgeView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(badgeView)

        NSLayoutConstraint.activate([
            badgeView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: 0),
            badgeView.topAnchor.constraint(equalTo: button.topAnchor, constant: -3)
        ])
    }

    // MARK: - Click Handling

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    // MARK: - Popover

    func showPopover() {
        guard let button = statusItem?.button else { return }
        popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hidePopover() {
        popover?.performClose(nil)
    }

    func togglePopover() {
        if popover?.isShown == true {
            hidePopover()
        } else {
            showPopover()
        }
    }

    private func repositionVisiblePopover() {
        guard let popover, popover.isShown else { return }
        hidePopover()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.showPopover()
        }
    }

    private func presentAppKitAlert(_ alertItem: AlertItem) {
        guard !isPresentingAlert else { return }
        isPresentingAlert = true

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "error.title")
        alert.informativeText = alertItem.message
        alert.addButton(withTitle: String(localized: "general.ok"))

        let completion: () -> Void = { [weak self] in
            guard let self else { return }
            self.isPresentingAlert = false
            self.appState?.alertItem = nil
        }

        if let window = popover?.contentViewController?.view.window {
            alert.beginSheetModal(for: window) { _ in
                completion()
            }
        } else {
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            completion()
        }
    }

    // MARK: - Context Menu

    private func showContextMenu() {
        guard let button = statusItem?.button else { return }

        let menu = buildContextMenu()
        statusItem?.menu = menu
        button.performClick(nil)
        statusItem?.menu = nil
    }

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()

        // Notifications
        let notificationsItem = NSMenuItem(
            title: String(localized: "notifications.title"),
            action: #selector(menuNotificationsClicked),
            keyEquivalent: ""
        )
        notificationsItem.target = self
        menu.addItem(notificationsItem)

        // Settings
        let settingsItem = NSMenuItem(
            title: String(localized: "settings.title"),
            action: #selector(menuSettingsClicked),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // Logout (only if authenticated)
        if appState?.isAuthenticated == true {
            let logoutItem = NSMenuItem(
                title: String(localized: "settings.logout"),
                action: #selector(menuLogoutClicked),
                keyEquivalent: ""
            )
            logoutItem.target = self
            menu.addItem(logoutItem)

            menu.addItem(NSMenuItem.separator())
        }

        // Quit
        let quitItem = NSMenuItem(
            title: String(localized: "menu.quit"),
            action: #selector(menuQuitClicked),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Menu Actions

    @objc private func menuNotificationsClicked() {
        showPopover()
    }

    @objc private func menuSettingsClicked() {
        hidePopover()
        guard let appState, let notificationListViewModel else { return }
        SettingsWindowManager.shared.showSettings(
            appState: appState,
            notificationListViewModel: notificationListViewModel
        )
    }

    @objc private func menuLogoutClicked() {
        hidePopover()
        guard let appState = appState else { return }
        Task {
            await appState.logout()
        }
    }

    @objc private func menuQuitClicked() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Popover Sizing

    /// Animates popover content size to fit current step. Used by AuthView wizard.
    @MainActor
    func setPopoverContentSize(width: CGFloat, height: CGFloat, animated: Bool = true) {
        guard let popover else { return }
        let target = NSSize(width: width, height: height)
        if animated, popover.isShown {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.28
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                ctx.allowsImplicitAnimation = true
                popover.contentSize = target
            }
        } else {
            popover.contentSize = target
        }
    }

    // MARK: - Cleanup

    deinit {
        if let eventMonitor = eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
        }
        cancellables.removeAll()
    }
}

// MARK: - Badge View

private class BadgeView: NSView {
    private let text: String

    init(text: String) {
        self.text = text
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .bold)
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let width = max(textSize.width + 6, 14)
        return NSSize(width: width, height: 14)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let path = NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7)
        NSColor.red.setFill()
        path.fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let textRect = NSRect(
            x: (bounds.width - textSize.width) / 2,
            y: (bounds.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        (text as NSString).draw(in: textRect, withAttributes: attributes)
    }
}
