import Combine
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var notifications: [MegaplanNotification] = []
    @Published var unreadCount: Int = 0
    @Published var firstName: String = ""
    @Published var apiUnreadCount: Int = 0
    
    /// Количество непрочитанных уведомлений для отображения в бейдже
    var unreadNotificationsCount: Int {
        notifications.filter { !$0.isRead }.count
    }
    @Published var isAuthenticated: Bool = false
    @Published var isLoading: Bool = false
    @Published var alertItem: AlertItem?
    @Published var domain: String
    @Published var username: String
    @Published var refreshInterval: Double
    @Published var autoLaunchEnabled: Bool
    @Published var tempCredentials: MegaplanCredentials

    private let api = MegaplanAPI()
    private let keychain = KeychainManager()
    private let userDefaults: UserDefaults
    private var refreshTimer: AnyCancellable?
    private var accessToken: String?
    private var cachedPassword: String?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let domainValue = userDefaults.string(forKey: Constants.UserDefaultsKeys.domain) ?? ""
        let usernameValue = userDefaults.string(forKey: Constants.UserDefaultsKeys.username) ?? ""
        self.domain = domainValue
        self.username = usernameValue
        let storedInterval = userDefaults.double(forKey: Constants.UserDefaultsKeys.refreshInterval)
        if storedInterval > 0 {
            self.refreshInterval = storedInterval
        } else {
            self.refreshInterval = Constants.defaultRefreshInterval
        }
        self.autoLaunchEnabled = userDefaults.bool(forKey: Constants.UserDefaultsKeys.autoLaunch)
        
        // Initialize tempCredentials using local variables
        self.tempCredentials = MegaplanCredentials(
            domain: domainValue,
            login: usernameValue,
            password: ""
        )
        
        // Set domain in API if available
        if !self.domain.isEmpty {
            api.updateDomain(self.domain)
        }
        
        // Update unreadCount from API counter
        $apiUnreadCount
            .assign(to: &$unreadCount)

        Task {
            await restoreSession()
        }
    }

    func signIn(domain: String, login: String, password: String) async {
        isLoading = true
        defer { isLoading = false }

        let trimmedDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLogin = login.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedDomain.isEmpty, !trimmedLogin.isEmpty, !password.isEmpty else {
            presentError(.validationFailed)
            return
        }

        api.updateDomain(trimmedDomain)
        do {
            let token = try await api.authenticate(login: trimmedLogin, password: password)
            try persistCredentials(domain: trimmedDomain, login: trimmedLogin, password: password, token: token)
            isAuthenticated = true
            AppLogger.info("Authentication succeeded for \(trimmedLogin)")
            startRefreshTimer()
            await refresh()
        } catch {
            AppLogger.error("Authentication failed: \(error.localizedDescription)")
            presentError(NetworkError(error))
        }
    }

    func logout() {
        let currentUsername = username
        let currentDomain = domain

        accessToken = nil
        
        // Securely clear cached password from memory
        if var password = cachedPassword {
            password.removeAll()
        }
        cachedPassword = nil
        
        isAuthenticated = false
        notifications = []
        unreadCount = 0
        stopRefreshTimer()

        do {
            try keychain.delete(service: Constants.Keychain.service, account: Constants.Keychain.tokenAccount)
            if !currentUsername.isEmpty {
                let account = Constants.Keychain.passwordAccount(for: currentUsername, domain: currentDomain)
                try keychain.delete(service: Constants.Keychain.service, account: account)
            }
            AppLogger.info("User logged out")
        } catch {
            AppLogger.error("Failed to clear keychain during logout: \(error.localizedDescription)")
        }

        // Don't clear tempCredentials to allow copy-pasting data
        // Clear only the persisted credentials
        domain = ""
        username = ""

        userDefaults.removeObject(forKey: Constants.UserDefaultsKeys.domain)
        userDefaults.removeObject(forKey: Constants.UserDefaultsKeys.username)
    }

    func refreshNow() {
        Task {
            await refresh()
        }
    }

    func updateRefreshInterval(_ interval: Double) {
        let clampedInterval = max(15, interval)
        refreshInterval = clampedInterval
        userDefaults.set(clampedInterval, forKey: Constants.UserDefaultsKeys.refreshInterval)
        AppLogger.debug("Refresh interval updated to \(clampedInterval) seconds")
        startRefreshTimer()
    }

    func updateTempCredentials(_ credentials: MegaplanCredentials) {
        tempCredentials = credentials
    }
    
    func updateAutoLaunch(enabled: Bool) {
        autoLaunchEnabled = enabled
        userDefaults.set(enabled, forKey: Constants.UserDefaultsKeys.autoLaunch)

        // Modern API for macOS 13.0+ (minimum deployment target)
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            AppLogger.info("Auto launch updated: \(enabled)")
        } catch {
            AppLogger.error("Failed to update auto launch: \(error.localizedDescription)")
            autoLaunchEnabled = !enabled
            userDefaults.set(autoLaunchEnabled, forKey: Constants.UserDefaultsKeys.autoLaunch)
            presentError(.autoLaunchFailure)
        }
    }

    func markNotificationAsRead(_ notification: MegaplanNotification) {
        guard let token = accessToken else {
            presentError(.missingToken)
            return
        }

        Task {
            do {
                try await api.markAsRead(id: notification.id, token: token)
                notifications.removeAll { $0.id == notification.id }
                unreadCount = max(unreadCount - 1, 0)
                AppLogger.debug("Notification \(notification.id) marked as read")
            } catch {
                AppLogger.error("Failed to mark notification as read: \(error.localizedDescription)")
                presentError(NetworkError(error))
            }
        }
    }

    private func restoreSession() async {
        guard !domain.isEmpty else {
            AppLogger.debug("No stored domain, skipping session restore")
            return
        }

        api.updateDomain(domain)
        do {
            if let token = try keychain.read(service: Constants.Keychain.service, account: Constants.Keychain.tokenAccount) {
                accessToken = token
            }
            if !username.isEmpty {
                let account = Constants.Keychain.passwordAccount(for: username, domain: domain)
                cachedPassword = try? keychain.read(service: Constants.Keychain.service, account: account)
            }
        } catch {
            AppLogger.error("Failed to read credentials from keychain: \(error.localizedDescription)")
        }

        guard let token = accessToken else {
            AppLogger.debug("No token available, showing auth view")
            return
        }

        do {
            let result = try await api.validateToken(token: token)
            if result.isValid {
                isAuthenticated = true
                if let firstName = result.firstName {
                    self.firstName = firstName
                }
                if let unreadCount = result.unreadCount {
                    self.apiUnreadCount = unreadCount
                }
                AppLogger.info("Token validation succeeded, restoring session")
                startRefreshTimer()
                await refresh()
            } else if let password = cachedPassword {
                AppLogger.debug("Token invalid, attempting re-authentication")
                await signIn(domain: domain, login: username, password: password)
            } else {
                AppLogger.debug("Token invalid and no password cached")
                logout()
            }
        } catch NetworkError.unauthorized {
            AppLogger.debug("Token unauthorized, attempting re-authentication")
            if let password = cachedPassword {
                await signIn(domain: domain, login: username, password: password)
            } else {
                logout()
            }
        } catch {
            AppLogger.error("Token validation failed: \(error.localizedDescription)")
            presentError(NetworkError(error))
        }
    }

    private func refresh() async {
        guard let token = accessToken else {
            AppLogger.debug("Refresh called but no access token")
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            async let notificationsTask = api.fetchNotifications(token: token)
            async let counterTask = api.fetchUnreadCount(token: token)

            let (fetchedNotifications, counter) = try await (notificationsTask, counterTask)
            
            withAnimation(.easeInOut) {
                notifications = fetchedNotifications
            }
            
            apiUnreadCount = counter
            AppLogger.debug("Refreshed: \(fetchedNotifications.count) notifications, \(counter) unread")
        } catch NetworkError.unauthorized {
            AppLogger.error("Unauthorized during refresh")
            isAuthenticated = false
            accessToken = nil
            stopRefreshTimer()
            presentError(.sessionExpired)
        } catch {
            AppLogger.error("Refresh failed: \(error.localizedDescription)")
            presentError(NetworkError(error))
        }
    }

    private func startRefreshTimer() {
        refreshTimer?.cancel()
        guard isAuthenticated else { return }

        refreshTimer = Timer.publish(every: refreshInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.refresh() }
            }
    }

    private func stopRefreshTimer() {
        refreshTimer?.cancel()
        refreshTimer = nil
    }

    private func persistCredentials(domain: String, login: String, password: String, token: String) throws {
        accessToken = token
        cachedPassword = password

        username = login
        self.domain = domain

        userDefaults.set(domain, forKey: Constants.UserDefaultsKeys.domain)
        userDefaults.set(login, forKey: Constants.UserDefaultsKeys.username)

        try keychain.save(token, service: Constants.Keychain.service, account: Constants.Keychain.tokenAccount)
        let account = Constants.Keychain.passwordAccount(for: login, domain: domain)
        try keychain.save(password, service: Constants.Keychain.service, account: account)
    }

    private func presentError(_ error: NetworkError) {
        alertItem = AlertItem(message: error.localizedDescription)
    }
}

struct AlertItem: Identifiable {
    let id = UUID()
    let message: String
}
