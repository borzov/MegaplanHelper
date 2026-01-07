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
    @Published var isAdmin: Bool = false
    @Published var isAuthenticated: Bool = false
    @Published var isLoading: Bool = false
    @Published var isOffline: Bool = false
    @Published var lastSyncTime: Date?
    @Published var alertItem: AlertItem?
    @Published var domain: String
    @Published var username: String
    @Published var refreshInterval: Double
    @Published var autoLaunchEnabled: Bool
    @Published var tempCredentials: MegaplanCredentials

    let api: AuthenticationService & NotificationService
    private let keychain = KeychainManager()
    private let userDefaults: UserDefaults
    private let notificationManager = NotificationManager.shared
    private let errorRecoveryService = ErrorRecoveryService.shared
    private var refreshTimerTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var accessToken: String?
    private var cachedPasswordData: Data?
    private var lastRefreshTime: Date?
    private let minimumRefreshInterval: TimeInterval = 5.0
    private var failedLoginAttempts = 0
    private var lastFailedLoginTime: Date?
    private var lastSuccessfulNotifications: [MegaplanNotification] = []
    private var lastSuccessfulUnreadCount: Int = 0

    init(
        api: AuthenticationService & NotificationService = MegaplanAPI(),
        userDefaults: UserDefaults = .standard
    ) {
        self.api = api
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
            (api as? MegaplanAPI)?.updateDomain(self.domain)
        }
        
        // Update unreadCount from API counter
        $apiUnreadCount
            .assign(to: &$unreadCount)

        // Запрашиваем разрешение на уведомления при запуске
        Task {
            _ = await notificationManager.requestAuthorization()
        }

        Task {
            await restoreSession()
        }
    }

    func signIn(domain: String, login: String, password: String) async {
        // Check for brute force protection
        if failedLoginAttempts >= 3,
           let lastTime = lastFailedLoginTime,
           Date().timeIntervalSince(lastTime) < 60 {
            presentError(.tooManyAttempts)
            return
        }
        
        isLoading = true
        defer { isLoading = false }

        let trimmedDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLogin = login.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedDomain.isEmpty, 
              isValidEmail(trimmedLogin), 
              !password.isEmpty else {
            presentError(.validationFailed)
            return
        }

        (api as? MegaplanAPI)?.updateDomain(trimmedDomain)
        do {
            let token = try await api.authenticate(login: trimmedLogin, password: password)
            try persistCredentials(domain: trimmedDomain, login: trimmedLogin, password: password, token: token)
            isAuthenticated = true
            
            // Validate token and check admin permissions
            do {
                let result = try await api.validateToken(token: token)
                if let firstName = result.firstName {
                    self.firstName = firstName
                }
                if let unreadCount = result.unreadCount {
                    self.apiUnreadCount = unreadCount
                }
                // Check admin permissions
                self.isAdmin = Constants.AdminPermissions.isAdministrator(result.possibleActions)
                AppLogger.info("Authentication succeeded for \(trimmedLogin). Admin: \(isAdmin)")
            } catch {
                AppLogger.warning("Failed to validate token after authentication: \(error.localizedDescription)")
                // Continue anyway, admin check will happen on next token validation
            }
            
            // Reset failed attempts on success
            failedLoginAttempts = 0
            lastFailedLoginTime = nil
            
            startRefreshTimer()
            await refresh()
        } catch {
            // Increment failed attempts
            failedLoginAttempts += 1
            lastFailedLoginTime = Date()
            
            AppLogger.error("Authentication failed: \(error.localizedDescription)")
            presentError(NetworkError(error))
        }
    }

    func logout() {
        let currentUsername = username
        let currentDomain = domain

        accessToken = nil
        clearCachedPassword()
        
        isAuthenticated = false
        notifications = []
        unreadCount = 0
        isAdmin = false
        firstName = ""
        isOffline = false
        lastSuccessfulNotifications = []
        lastSuccessfulUnreadCount = 0
        stopRefreshTimer()
        
        // Clear user info cache
        Task {
            await UserInfoCache.shared.clearCache()
            AppLogger.debug("Cleared user info cache")
        }

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
        if let lastTime = lastRefreshTime,
           Date().timeIntervalSince(lastTime) < minimumRefreshInterval {
            AppLogger.debug("Refresh throttled - too soon since last refresh")
            return
        }
        
        lastRefreshTime = Date()
        refreshTask?.cancel()
        refreshTask = Task {
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
        
        // Save notification for potential rollback
        let notificationCopy = notification
        Task {
            // Optimistic UI update
            await MainActor.run {
                withAnimation {
                    notifications.removeAll { $0.id == notification.id }
                    unreadCount = max(unreadCount - 1, 0)
                }
            }
            
            do {
                try await api.markAsRead(id: notification.id, token: token)
                AppLogger.debug("Notification \(notification.id) marked as read")
            } catch {
                // Rollback on error
                await MainActor.run {
                    withAnimation {
                        notifications.insert(notificationCopy, at: 0)
                        unreadCount += 1
                    }
                }
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

        (api as? MegaplanAPI)?.updateDomain(domain)
        do {
            if let token = try keychain.read(service: Constants.Keychain.service, account: Constants.Keychain.tokenAccount) {
                accessToken = token
            }
            if !username.isEmpty {
                let account = Constants.Keychain.passwordAccount(for: username, domain: domain)
                if let passwordString = try? keychain.read(service: Constants.Keychain.service, account: account) {
                    cachedPasswordData = passwordString.data(using: .utf8)
                }
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
                // Check admin permissions
                self.isAdmin = Constants.AdminPermissions.isAdministrator(result.possibleActions)
                AppLogger.info("Token validation succeeded, restoring session. Admin: \(isAdmin)")
                startRefreshTimer()
                await refresh()
            } else if let passwordData = cachedPasswordData,
                      let password = String(data: passwordData, encoding: .utf8) {
                AppLogger.debug("Token invalid, attempting re-authentication")
                await signIn(domain: domain, login: username, password: password)
            } else {
                AppLogger.debug("Token invalid and no password cached")
                logout()
            }
        } catch NetworkError.unauthorized {
            AppLogger.debug("Token unauthorized, attempting re-authentication")
            if let passwordData = cachedPasswordData,
               let password = String(data: passwordData, encoding: .utf8) {
                await signIn(domain: domain, login: username, password: password)
            } else {
                logout()
            }
        } catch {
            AppLogger.error("Token validation failed: \(error.localizedDescription)")
            presentError(NetworkError(error))
        }
    }

    func refresh() async {
        guard !Task.isCancelled else { return }
        guard let token = accessToken else {
            AppLogger.debug("Refresh called but no access token")
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            // Используем retry механизм для загрузки уведомлений
            let (fetchedNotifications, counter) = try await errorRecoveryService.executeWithRetry(
                operation: {
                    async let notificationsTask = self.api.fetchNotifications(token: token)
                    async let counterTask = self.api.fetchUnreadCount(token: token)
                    return try await (notificationsTask, counterTask)
                },
                onRetry: { attempt, delay in
                    AppLogger.info("Retrying refresh after \(delay)s (attempt \(attempt))")
                },
                onFailure: { error in
                    AppLogger.error("All retry attempts failed: \(error.localizedDescription)")
                }
            )
            
            // Успешное обновление - выходим из оффлайн-режима
            isOffline = false
            lastSyncTime = Date()

            // Определяем новые непрочитанные уведомления
            let previousNotificationIDs = Set(notifications.map { $0.id })
            let newUnreadNotifications = fetchedNotifications.filter { notification in
                !previousNotificationIDs.contains(notification.id) && !notification.isRead
            }
            
            // Отправляем уведомления для новых непрочитанных
            for notification in newUnreadNotifications {
                notificationManager.sendNotification(for: notification)
            }
            
            // Сохраняем успешные данные для оффлайн-режима
            lastSuccessfulNotifications = fetchedNotifications
            lastSuccessfulUnreadCount = counter
            
            withAnimation(.easeInOut) {
                notifications = fetchedNotifications
            }
            
            apiUnreadCount = counter
            AppLogger.debug("Refreshed: \(fetchedNotifications.count) notifications, \(counter) unread, \(newUnreadNotifications.count) new unread")
        } catch NetworkError.offline {
            // Переход в оффлайн-режим без показа ошибки
            AppLogger.info("No internet connection, entering offline mode")
            isOffline = true
            
            // Используем последние успешные данные, если они есть
            if !lastSuccessfulNotifications.isEmpty {
                withAnimation(.easeInOut) {
                    notifications = lastSuccessfulNotifications
                }
                apiUnreadCount = lastSuccessfulUnreadCount
                AppLogger.debug("Using cached data in offline mode: \(lastSuccessfulNotifications.count) notifications")
            }
        } catch NetworkError.unauthorized {
            AppLogger.error("Unauthorized during refresh")
            isAuthenticated = false
            accessToken = nil
            stopRefreshTimer()
            presentError(.sessionExpired)
        } catch {
            // Для других ошибок проверяем, не связаны ли они с сетью
            if let networkError = error as? NetworkError,
               case .transport = networkError {
                // Проверяем, не является ли это сетевой ошибкой
                if let urlError = (error as NSError).userInfo[NSUnderlyingErrorKey] as? URLError,
                   urlError.code == .notConnectedToInternet || urlError.code == .networkConnectionLost {
                    isOffline = true
                    if !lastSuccessfulNotifications.isEmpty {
                        withAnimation(.easeInOut) {
                            notifications = lastSuccessfulNotifications
                        }
                        apiUnreadCount = lastSuccessfulUnreadCount
                    }
                    AppLogger.info("Network error detected, entering offline mode")
                    return
                }
            }
            
            AppLogger.error("Refresh failed: \(error.localizedDescription)")
            // Не показываем ошибку для сетевых проблем в оффлайн-режиме
            if !isOffline {
                presentError(NetworkError(error))
            }
        }
    }

    private func startRefreshTimer() {
        refreshTimerTask?.cancel()
        guard isAuthenticated else { return }
        
        refreshTimerTask = Task { @MainActor in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(refreshInterval * 1_000_000_000))
                } catch {
                    // Task was cancelled
                    break
                }
                
                guard !Task.isCancelled else { break }
                await refresh()
            }
        }
    }

    private func stopRefreshTimer() {
        refreshTimerTask?.cancel()
        refreshTimerTask = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func persistCredentials(domain: String, login: String, password: String, token: String) throws {
        accessToken = token
        cachedPasswordData = password.data(using: .utf8)

        username = login
        self.domain = domain

        userDefaults.set(domain, forKey: Constants.UserDefaultsKeys.domain)
        userDefaults.set(login, forKey: Constants.UserDefaultsKeys.username)

        try keychain.save(token, service: Constants.Keychain.service, account: Constants.Keychain.tokenAccount)
        let account = Constants.Keychain.passwordAccount(for: login, domain: domain)
        try keychain.save(password, service: Constants.Keychain.service, account: account)
    }
    
    private func clearCachedPassword() {
        // Securely clear password from memory
        guard var data = cachedPasswordData else { return }
        data.resetBytes(in: 0..<data.count)
        cachedPasswordData = nil
    }

    private func presentError(_ error: NetworkError) {
        alertItem = AlertItem(message: error.localizedDescription)
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
}

struct AlertItem: Identifiable {
    let id = UUID()
    let message: String
}
