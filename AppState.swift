import AppKit
import Combine
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    // Примечание: Некоторые свойства остаются публичными для поддержки SwiftUI Preview в DEBUG сборках
    #if DEBUG
    @Published var notifications: [MegaplanNotification] = []
    @Published var isAuthenticated: Bool = false
    #else
    @Published private(set) var notifications: [MegaplanNotification] = []
    @Published private(set) var isAuthenticated: Bool = false
    #endif
    @Published private(set) var unreadCount: Int = 0
    @Published private(set) var firstName: String = ""
    @Published private(set) var apiUnreadCount: Int = 0
    @Published private(set) var isAdmin: Bool = false
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isOffline: Bool = false
    @Published private(set) var isSessionExpired: Bool = false
    @Published private(set) var lastSyncTime: Date?
    @Published var alertItem: AlertItem?
    @Published private(set) var lockoutState: LockoutState?
    /// Not private(set): AuthView clears this when the user edits a field, so a binding-friendly setter is required.
    @Published var lastAuthError: AuthFieldError?
    /// Transient banner message shown briefly in the popover (e.g. "comments
    /// copied"). Auto-clears on its own; nil hides the banner.
    @Published var transientToast: String?
    @Published private(set) var certificatePinningFailed: Bool = false
    @Published private(set) var domain: String
    @Published private(set) var username: String
    @Published private(set) var refreshInterval: Double
    @Published private(set) var autoLaunchEnabled: Bool
    @Published var tempCredentials: MegaplanCredentials

    // MARK: - Tasks tab state
    @Published private(set) var tasks: [MegaplanTask] = []
    @Published private(set) var isTasksLoading: Bool = false
    @Published private(set) var taskSortKey: TaskSortKey = .activity
    @Published private(set) var taskStatusFilter: TaskStatusFilter = .active
    @Published private(set) var lastTasksSyncTime: Date?
    @Published private(set) var tasksUnreadCount: Int = 0

    // MARK: - Settings UI helpers

    /// Human-readable representation of the last successful notifications sync,
    /// suitable for AccountCard. Returns nil when no sync has occurred yet.
    var formattedLastSync: String? {
        guard let lastSyncTime else { return nil }
        return DateFormatters.relative(lastSyncTime)
    }

    /// Cached avatar of the currently signed-in user. Owned by AppState
    /// (set by the avatar loader). AccountCard observes this for display.
    /// TODO(Phase 2): wire up the loader once `EmployeeService` exposes the
    /// avatar URL for the authenticated user. Until then, `AccountCard` shows
    /// the initials gradient fallback — there is no functional regression
    /// because the previous SettingsView never displayed an avatar either.
    @Published private(set) var currentUserAvatar: NSImage?

    let api: AuthenticationService & NotificationService & TaskService & EmployeeService
    private var currentUserId: String?
    private let keychain = KeychainManager()
    private let userDefaults: UserDefaults
    private let notificationManager = NotificationManager.shared
    private let errorRecoveryService = ErrorRecoveryService.shared
    private let refreshScheduler: RefreshScheduler
    private var refreshTask: Task<Void, Never>?
    private var certificatePinningObserver: (any NSObjectProtocol)?
    private var accessToken: String?
    private var cachedPasswordData: Data?
    private var lastRefreshTime: Date?
    private let minimumRefreshInterval: TimeInterval = 5.0
    private static let lockoutDuration: TimeInterval = 15 * 60
    private var failedLoginAttempts = 0
    private var lastFailedLoginTime: Date?
    private var lastSuccessfulNotifications: [MegaplanNotification] = []
    private var lastSuccessfulUnreadCount: Int = 0
    private var isShuttingDown = false
    private var isSessionRestored = false

    init(
        api: AuthenticationService & NotificationService & TaskService & EmployeeService = MegaplanAPI(),
        userDefaults: UserDefaults = .standard
    ) {
        self.api = api
        self.userDefaults = userDefaults
        let domainValue = userDefaults.string(forKey: Constants.UserDefaultsKeys.domain) ?? ""
        let usernameValue = userDefaults.string(forKey: Constants.UserDefaultsKeys.username) ?? ""
        self.domain = domainValue
        self.username = usernameValue
        let storedInterval = userDefaults.double(forKey: Constants.UserDefaultsKeys.refreshInterval)
        let intervalValue: TimeInterval
        if storedInterval > 0 {
            intervalValue = storedInterval
            self.refreshInterval = storedInterval
        } else {
            intervalValue = Constants.defaultRefreshInterval
            self.refreshInterval = Constants.defaultRefreshInterval
        }
        self.autoLaunchEnabled = userDefaults.bool(forKey: Constants.UserDefaultsKeys.autoLaunch)
        self.refreshScheduler = RefreshScheduler(interval: intervalValue)

        if let storedSort = userDefaults.string(forKey: Constants.UserDefaultsKeys.taskSortKey),
           let sortKey = TaskSortKey(rawValue: storedSort) {
            self.taskSortKey = sortKey
        }
        if let storedFilter = userDefaults.string(forKey: Constants.UserDefaultsKeys.taskStatusFilter),
           let filter = TaskStatusFilter(rawValue: storedFilter) {
            self.taskStatusFilter = filter
        }
        
        // Инициализация tempCredentials используя локальные переменные
        self.tempCredentials = MegaplanCredentials(
            domain: domainValue,
            login: usernameValue,
            password: ""
        )
        
        // Устанавливаем domain в API если доступен
        if !self.domain.isEmpty {
            (api as? MegaplanAPI)?.updateDomain(self.domain)
        }
        
        // Синхронизация unreadCount с счётчиком из API
        $apiUnreadCount
            .assign(to: &$unreadCount)

        // Запрашиваем разрешение на уведомления при запуске.
        // Захватываем notificationManager локально — он singleton, weak self не нужен.
        Task { [notificationManager] in
            _ = await notificationManager.requestAuthorization()
        }

        // Wire UserInfoResolver so any view can lazily look up an employee by id
        // without holding a direct reference to the API or the access token.
        let resolverApi = api
        Task { [weak self] in
            await UserInfoResolver.shared.configure(
                api: resolverApi,
                tokenProvider: { [weak self] in
                    await MainActor.run { self?.accessToken }
                }
            )
        }

        // Subscribe to certificate pinning failure notifications.
        // Сохраняем токен наблюдателя, чтобы корректно снять подписку в deinit.
        // Closure доставляется на main queue → используем assumeIsolated для @MainActor мутаций.
        certificatePinningObserver = NotificationCenter.default.addObserver(
            forName: .certificatePinningFailed,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            let host = notification.userInfo?["host"] as? String ?? "unknown"
            AppLogger.warning("Certificate pinning failed for \(host) — showing warning to user")
            MainActor.assumeIsolated {
                self.certificatePinningFailed = true
                self.alertItem = AlertItem(
                    message: String(localized: "security.pinning.warning")
                )
            }
        }

        Task { [weak self] in
            await self?.restoreSession()
        }
    }

    func signIn(domain: String, login: String, password: String) async {
        // Brute force protection: 15 minutes lockout after 3 failed attempts
        if failedLoginAttempts >= 3,
           let lastTime = lastFailedLoginTime {
            if Date().timeIntervalSince(lastTime) < Self.lockoutDuration {
                lastAuthError = .lockout
                recomputeLockoutState()
                return
            } else {
                // Lockout period has expired, reset the counter
                failedLoginAttempts = 0
                lastFailedLoginTime = nil
                recomputeLockoutState()
            }
        }
        
        isLoading = true
        defer { isLoading = false }

        let trimmedDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLogin = login.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedDomain.isEmpty {
            lastAuthError = .domain(.invalidFormat)
            return
        }
        if !trimmedLogin.isValidEmail() {
            lastAuthError = .credentials(.invalidEmail)
            return
        }
        if password.isEmpty {
            lastAuthError = .credentials(.emptyPassword)
            return
        }

        (api as? MegaplanAPI)?.updateDomain(trimmedDomain)
        do {
            let token = try await api.authenticate(login: trimmedLogin, password: password)
            try persistCredentials(domain: trimmedDomain, login: trimmedLogin, password: password, token: token)
            lastAuthError = nil
            isAuthenticated = true

            // Validate token and check admin permissions
            do {
                let result = try await api.validateToken(token: token)
                applyTokenValidationResult(result)
                AppLogger.info("Authentication succeeded for \(trimmedLogin). Admin: \(isAdmin)")
            } catch {
                AppLogger.warning("Failed to validate token after authentication: \(error.localizedDescription)")
                // Continue anyway, admin check will happen on next token validation
            }

            // Reset failed attempts on success
            failedLoginAttempts = 0
            lastFailedLoginTime = nil
            recomputeLockoutState()

            // Clear cached password after successful authentication if session was already restored
            // This reduces the time password stays in memory
            if isSessionRestored {
                AppLogger.info("Clearing cached password after successful authentication")
                clearCachedPassword()
            }

            startRefreshTimer()
            await refresh()
        } catch {
            // Increment failed attempts
            failedLoginAttempts += 1
            lastFailedLoginTime = Date()
            recomputeLockoutState()

            let networkError = NetworkError(error)
            AppLogger.error("Authentication failed: \(networkError.localizedDescription)")
            lastAuthError = AuthFieldError(networkError: networkError)
        }
    }

    func logout() {
        isShuttingDown = true

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
        isSessionExpired = false
        certificatePinningFailed = false
        lastSuccessfulNotifications = []
        lastSuccessfulUnreadCount = 0
        tasks = []
        tasksUnreadCount = 0
        currentUserId = nil
        lastTasksSyncTime = nil
        stopRefreshTimer()

        isShuttingDown = false

        // Reset certificate pinning state for next session
        MegaplanAPI.resetPinningState()
        
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

        // Очистка пароля из tempCredentials для безопасности, сохраняя domain/login для удобства
        tempCredentials.password = ""

        domain = ""
        username = ""

        userDefaults.removeObject(forKey: Constants.UserDefaultsKeys.domain)
        userDefaults.removeObject(forKey: Constants.UserDefaultsKeys.username)
    }

    // MARK: - Admin diagnostics (Settings → About → Quick links)

    /// Copies a sanitised diagnostic log to the system pasteboard.
    /// Admin-only convenience for support tickets. Stub for now — full log
    /// pipeline can be wired up later without breaking AboutView.
    func copyLogToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let summary = """
        MegaplanHelper diagnostic snapshot
        Domain: \(domain)
        User: \(username)
        Authenticated: \(isAuthenticated)
        Last sync: \(lastSyncTime?.description ?? "never")
        Notifications: \(notifications.count)
        Tasks: \(tasks.count)
        """
        pasteboard.setString(summary, forType: .string)
    }

    /// Optional URL for the workspace's knowledge base. Returns nil unless
    /// the workspace exposes one — Phase 1 returns nil pending integration.
    var knowledgeBaseURL: URL? {
        guard !domain.isEmpty,
              let host = URL(string: domain.hasPrefix("http") ? domain : "https://\(domain)")?.host else {
            return nil
        }
        return URL(string: "https://\(host)/knowledge")
    }

    /// Workspace deals dashboard URL.
    var dealsURL: URL? {
        guard !domain.isEmpty,
              let host = URL(string: domain.hasPrefix("http") ? domain : "https://\(domain)")?.host else {
            return nil
        }
        return URL(string: "https://\(host)/deals")
    }

    /// Workspace tasks dashboard URL.
    var tasksURL: URL? {
        guard !domain.isEmpty,
              let host = URL(string: domain.hasPrefix("http") ? domain : "https://\(domain)")?.host else {
            return nil
        }
        return URL(string: "https://\(host)/tasks")
    }

    func refreshNow() {
        if let lastTime = lastRefreshTime,
           Date().timeIntervalSince(lastTime) < minimumRefreshInterval {
            AppLogger.debug("Refresh throttled - too soon since last refresh")
            return
        }
        
        lastRefreshTime = Date()
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.refresh()
        }
    }

    func updateRefreshInterval(_ interval: Double) {
        let clampedInterval = max(15, interval)
        refreshInterval = clampedInterval
        userDefaults.set(clampedInterval, forKey: Constants.UserDefaultsKeys.refreshInterval)
        AppLogger.debug("Refresh interval updated to \(clampedInterval) seconds")

        Task {
            await refreshScheduler.updateInterval(clampedInterval) { [weak self] in
                await self?.refresh()
            }
        }
    }

    func updateTempCredentials(_ credentials: MegaplanCredentials) {
        tempCredentials = credentials
    }
    
    func updateTaskSortKey(_ key: TaskSortKey) {
        guard key != taskSortKey else { return }
        taskSortKey = key
        userDefaults.set(key.rawValue, forKey: Constants.UserDefaultsKeys.taskSortKey)
        refreshNow()
    }

    /// Pulls all comments for `task` and copies a markdown export to the
    /// clipboard. Returns the comment count on success, `nil` on transport
    /// failure, and `0` when the task has no comments at all. Shows a
    /// transient banner so the user gets visible feedback either way.
    @discardableResult
    func copyTaskCommentsAsMarkdown(for task: MegaplanTask) async -> Int? {
        guard let token = accessToken else {
            showTransientToast(String(localized: "tasks.markdown.failed"))
            return nil
        }
        do {
            let bundle = try await api.fetchTaskComments(token: token, taskId: task.id)
            guard !bundle.comments.isEmpty else {
                showTransientToast(String(localized: "tasks.markdown.empty"))
                return 0
            }
            let markdown = MarkdownCommentExporter.export(
                bundle: bundle,
                taskURL: task.webURL(host: domain)
            )
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(markdown, forType: .string)
            AppLogger.info("Copied markdown for task \(task.id): \(bundle.comments.count) comments, \(markdown.count) chars")
            let summary = String(format: String(localized: "tasks.markdown.copied.format"),
                                 bundle.comments.count,
                                 Pluralization.form(count: bundle.comments.count,
                                                    one: String(localized: "comments.one"),
                                                    few: String(localized: "comments.few"),
                                                    many: String(localized: "comments.many")))
            showTransientToast(summary)
            return bundle.comments.count
        } catch {
            AppLogger.warning("copyTaskCommentsAsMarkdown failed for \(task.id): \(error.localizedDescription)")
            showTransientToast(String(localized: "tasks.markdown.failed"))
            return nil
        }
    }

    private var transientToastResetTask: Task<Void, Never>?

    func showTransientToast(_ message: String, duration: TimeInterval = 2.4) {
        transientToast = message
        transientToastResetTask?.cancel()
        transientToastResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if Task.isCancelled { return }
            await MainActor.run {
                guard let self else { return }
                if self.transientToast == message {
                    self.transientToast = nil
                }
            }
        }
    }

    /// Server-side task search. Returns an empty array on missing session or any
    /// transport error — callers fall back to whatever is in the local cache.
    func searchTasks(query: String, limit: Int = 30) async -> [MegaplanTask] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token = accessToken,
              let userId = currentUserId,
              !userId.isEmpty,
              !trimmed.isEmpty else {
            return []
        }
        do {
            return try await api.searchTasks(token: token,
                                             currentUserId: userId,
                                             query: trimmed,
                                             limit: limit)
        } catch {
            AppLogger.warning("searchTasks failed: \(error.localizedDescription)")
            return []
        }
    }

    func updateTaskStatusFilter(_ filter: TaskStatusFilter) {
        guard filter != taskStatusFilter else { return }
        taskStatusFilter = filter
        userDefaults.set(filter.rawValue, forKey: Constants.UserDefaultsKeys.taskStatusFilter)
        refreshNow()
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
        Task { [weak self] in
            guard let self else { return }
            // Optimistic UI update
            await MainActor.run { [weak self] in
                guard let self else { return }
                withAnimation {
                    self.notifications.removeAll { $0.id == notification.id }
                    self.unreadCount = max(self.unreadCount - 1, 0)
                }
            }

            do {
                try await self.api.markAsRead(id: notification.id, token: token)
                AppLogger.debug("Notification \(notification.id) marked as read")
            } catch {
                // Rollback on error
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    withAnimation {
                        self.notifications.insert(notificationCopy, at: 0)
                        self.unreadCount += 1
                    }
                }
                AppLogger.error("Failed to mark notification as read: \(error.localizedDescription)")
                await MainActor.run { [weak self] in
                    self?.presentError(NetworkError(error))
                }
            }
        }
    }

    /// Returns the password saved for (domain, login) if it matches the
    /// currently-stored credentials, otherwise nil. Used by AuthView wizard
    /// to restore the password field when the user returns to Step 2.
    func loadSavedCredentialsFromKeychain(domain: String, login: String) async -> String? {
        let trimmedDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedLogin = login.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedDomain.isEmpty, !trimmedLogin.isEmpty else { return nil }

        let rawStoredDomain = userDefaults.string(forKey: Constants.UserDefaultsKeys.domain) ?? ""
        let storedDomain = rawStoredDomain.lowercased()
        let storedLogin = userDefaults.string(forKey: Constants.UserDefaultsKeys.username) ?? ""

        guard storedDomain == trimmedDomain, storedLogin == trimmedLogin else { return nil }

        let account = Constants.Keychain.passwordAccount(for: storedLogin, domain: rawStoredDomain)
        do {
            return try keychain.read(service: Constants.Keychain.service, account: account)
        } catch {
            AppLogger.warning("Keychain read failed in loadSavedCredentialsFromKeychain: \(error.localizedDescription)")
            return nil
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
                isSessionRestored = true
                applyTokenValidationResult(result)
                AppLogger.info("Token validation succeeded, restoring session. Admin: \(isAdmin)")
                startRefreshTimer()
                await refresh()

                // Clear cached password after successful session restore to minimize exposure time
                AppLogger.info("Clearing cached password after successful session restore")
                clearCachedPassword()
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

        // Lazily resolve current user id once per session — used by the tasks endpoint filter.
        if currentUserId == nil {
            do {
                currentUserId = try await api.fetchCurrentUserId(token: token)
                AppLogger.debug("Resolved currentUserId: \(currentUserId ?? "nil")")
            } catch {
                AppLogger.warning("Failed to resolve currentUserId: \(error.localizedDescription)")
            }
        }

        // Tasks fetch runs in parallel with notifications and is decoupled from retry logic
        // so a tasks failure cannot block the notification refresh path.
        let userIdForTasks = currentUserId
        let sortKey = taskSortKey
        let statusFilter = taskStatusFilter
        let tasksTask = Task<[MegaplanTask]?, Never> { [weak self] in
            guard let self, let uid = userIdForTasks, !uid.isEmpty else { return nil }
            await MainActor.run { self.isTasksLoading = true }
            defer {
                Task { @MainActor in self.isTasksLoading = false }
            }
            do {
                return try await self.api.fetchTasks(token: token,
                                                     currentUserId: uid,
                                                     sortBy: sortKey,
                                                     statusFilter: statusFilter,
                                                     limit: 100)
            } catch {
                AppLogger.warning("fetchTasks failed: \(error.localizedDescription)")
                return nil
            }
        }

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

            // Check for cancellation after async operation completes
            guard !Task.isCancelled else { return }

            // Success - exit offline mode and clear session expired flag
            isOffline = false
            isSessionExpired = false
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

            // Apply tasks result independently — failure here is non-fatal.
            if let fetchedTasks = await tasksTask.value {
                withAnimation(.easeInOut) {
                    tasks = fetchedTasks
                }
                tasksUnreadCount = fetchedTasks.reduce(0) { $0 + $1.unreadCommentsCount }
                lastTasksSyncTime = Date()
                AppLogger.debug("Refreshed: \(fetchedTasks.count) tasks, \(tasksUnreadCount) unread comments")
            }
        } catch NetworkError.offline {
            // Переход в оффлайн-режим без показа ошибки
            AppLogger.info("No internet connection, entering offline mode")
            isOffline = true
            restoreCachedNotifications()
        } catch NetworkError.unauthorized {
            AppLogger.error("Unauthorized during refresh - session expired")
            isSessionExpired = true
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
                    restoreCachedNotifications()
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
        guard isAuthenticated, !isShuttingDown else { return }

        Task {
            await refreshScheduler.start(interval: refreshInterval) { [weak self] in
                guard let self = self else { return }
                // Требуется await для доступа к @MainActor свойству из actor контекста
                if await self.isShuttingDown { return }
                await self.refresh()
            }
        }
    }

    private func stopRefreshTimer() {
        Task {
            await refreshScheduler.stop()
        }
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

    private func applyTokenValidationResult(_ result: (isValid: Bool, firstName: String?, unreadCount: Int?, possibleActions: [String]?)) {
        if let firstName = result.firstName {
            self.firstName = firstName
        }
        if let unreadCount = result.unreadCount {
            self.apiUnreadCount = unreadCount
        }
        self.isAdmin = Constants.AdminPermissions.isAdministrator(result.possibleActions)
    }

    private func restoreCachedNotifications() {
        guard !lastSuccessfulNotifications.isEmpty else { return }

        withAnimation(.easeInOut) {
            notifications = lastSuccessfulNotifications
        }
        apiUnreadCount = lastSuccessfulUnreadCount
        AppLogger.debug("Using cached data in offline mode (total: \(lastSuccessfulNotifications.count))")
    }

    private func presentError(_ error: NetworkError) {
        alertItem = AlertItem(message: error.localizedDescription)
    }

    private func recomputeLockoutState() {
        if failedLoginAttempts >= 3,
           let lastTime = lastFailedLoginTime,
           Date().timeIntervalSince(lastTime) < Self.lockoutDuration {
            lockoutState = LockoutState(
                lockedUntil: lastTime.addingTimeInterval(Self.lockoutDuration),
                attemptCount: failedLoginAttempts
            )
        } else {
            lockoutState = nil
        }
    }

    deinit {
        // Примечание: isShuttingDown нельзя установить в deinit из-за @MainActor изоляции,
        // но задачи будут отменены немедленно
        if let certificatePinningObserver {
            NotificationCenter.default.removeObserver(certificatePinningObserver)
        }
        // Захватываем actor-ссылку локально, чтобы closure не удерживала self после deinit.
        let scheduler = refreshScheduler
        Task {
            await scheduler.stop()
        }
        refreshTask?.cancel()
        transientToastResetTask?.cancel()
    }
}

struct AlertItem: Identifiable {
    let id = UUID()
    let message: String
}

// MARK: - RefreshScheduler

/// Thread-safe refresh timer scheduler using actor
actor RefreshScheduler {
    private var task: Task<Void, Never>?
    private var interval: TimeInterval
    private var isRunning: Bool = false

    init(interval: TimeInterval) {
        self.interval = interval
    }

    /// Starts the refresh timer with the given interval
    /// - Parameters:
    ///   - interval: Interval in seconds between refreshes
    ///   - action: Async action to perform on each tick
    func start(interval: TimeInterval, action: @escaping @Sendable () async -> Void) {
        // Cancel existing task first
        task?.cancel()

        self.interval = interval
        self.isRunning = true

        task = Task {
            while !Task.isCancelled {
                guard !Task.isCancelled else { break }

                do {
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } catch {
                    // Task was cancelled
                    break
                }

                guard !Task.isCancelled else { break }
                await action()
            }
            await self.markAsStopped()
        }

        AppLogger.debug("RefreshScheduler started with interval: \(interval)s")
    }

    /// Stops the refresh timer
    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
        AppLogger.debug("RefreshScheduler stopped")
    }

    /// Updates the interval and restarts if currently running
    func updateInterval(_ newInterval: TimeInterval, action: @escaping @Sendable () async -> Void) {
        self.interval = newInterval
        if isRunning {
            start(interval: newInterval, action: action)
        }
    }

    /// Returns whether the scheduler is currently running
    func getIsRunning() -> Bool {
        return isRunning
    }

    private func markAsStopped() {
        isRunning = false
    }
}
