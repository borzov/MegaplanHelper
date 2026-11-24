import Foundation

/// Обновление ленты уведомлений и задач. На время запроса это источник правды;
/// `AppState` после запроса копирует поля в `@Published`.
@MainActor
final class WorkspaceSync {
    private(set) var notifications: [MegaplanNotification] = []
    private(set) var tasks: [MegaplanTask] = []
    private(set) var unreadCount: Int = 0
    private(set) var isOffline: Bool = false
    private(set) var isSessionExpired: Bool = false
    internal(set) var isAuthenticated: Bool = false
    private(set) var lastSyncTime: Date?
    private(set) var tasksUnreadCount: Int = 0
    private(set) var lastTasksSyncTime: Date?
    private(set) var isTasksLoading: Bool = false
    private(set) var currentUserId: String?

    var domain: String = ""
    var taskSortKey: TaskSortKey = .activity
    var taskStatusFilter: TaskStatusFilter = .active
    var onChange: (() -> Void)?

    private var api: MegaplanAPI
    private let snapshotStore: NotificationsSnapshotStore
    private let poster: NotificationPoster
    private let now: () -> Date
    private let sleep: (TimeInterval) async throws -> Void

    /// 3 попытки, база 1 с, потолок 30 с. Числа не менять.
    private let maxRetries = 3
    private let baseDelay: TimeInterval = 1.0
    private let maxDelay: TimeInterval = 30.0

    private var lastSuccessfulNotifications: [MegaplanNotification] = []
    private var lastSuccessfulUnreadCount: Int = 0
    private var pendingAlert: NetworkError?
    /// Уже отмеченные прочитанными локально. Свежий ответ ленты может ещё содержать их,
    /// пока DELETE не догнал сервер. Пока id есть в ответе, карточку не показываем.
    private var locallyReadIDs: Set<String> = []

    init(
        api: MegaplanAPI,
        snapshotStore: NotificationsSnapshotStore,
        poster: NotificationPoster,
        now: @escaping () -> Date = Date.init,
        sleep: @escaping (TimeInterval) async throws -> Void = { delay in
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    ) {
        self.api = api
        self.snapshotStore = snapshotStore
        self.poster = poster
        self.now = now
        self.sleep = sleep
    }

    func updateAPI(_ api: MegaplanAPI) {
        self.api = api
    }

    func takePendingAlert() -> NetworkError? {
        defer { pendingAlert = nil }
        return pendingAlert
    }

    func reset() {
        notifications = []
        tasks = []
        unreadCount = 0
        isOffline = false
        isSessionExpired = false
        isAuthenticated = false
        lastSyncTime = nil
        tasksUnreadCount = 0
        lastTasksSyncTime = nil
        isTasksLoading = false
        currentUserId = nil
        lastSuccessfulNotifications = []
        lastSuccessfulUnreadCount = 0
        pendingAlert = nil
        locallyReadIDs = []
    }

    func restoreSnapshotIfAvailable() async {
        guard let workspaceKey = AppState.workspaceKey(from: domain) else { return }
        guard let snapshot = await snapshotStore.load(workspaceKey: workspaceKey) else { return }
        lastSuccessfulNotifications = snapshot.notifications
        lastSuccessfulUnreadCount = snapshot.unreadCount
        if notifications.isEmpty {
            notifications = snapshot.notifications
            unreadCount = snapshot.unreadCount
        }
    }

    func refresh() async {
        guard !Task.isCancelled else { return }
        pendingAlert = nil

        await resolveCurrentUserIDIfNeeded()
        let tasksTask = startTasksRefreshTask()

        do {
            let (fetchedNotifications, counter) = try await refreshNotificationsWithRetry()
            guard !Task.isCancelled else { return }
            await applySuccessfulRefresh(notifications: fetchedNotifications, unreadCounter: counter)
            await applyTasksResult(from: tasksTask)
        } catch NetworkError.offline {
            AppLogger.info("No internet connection, entering offline mode")
            isOffline = true
            restoreCachedNotifications()
        } catch NetworkError.unauthorized {
            AppLogger.error("Unauthorized during refresh - session expired")
            isSessionExpired = true
            isAuthenticated = false
            pendingAlert = .sessionExpired
        } catch {
            let mappedError = NetworkError(error)
            if isTransientNetworkFailure(mappedError) {
                isOffline = true
                restoreCachedNotifications()
                AppLogger.info("Transient network issue detected during refresh, entering offline mode")
                return
            }

            AppLogger.error("Refresh failed: \(error.localizedDescription)")
            if !isOffline {
                pendingAlert = mappedError
            }
        }
    }

    func markNotificationAsRead(_ notification: MegaplanNotification) async -> NetworkError? {
        let notificationCopy = notification
        locallyReadIDs.insert(notification.id)
        notifications.removeAll { $0.id == notification.id }
        unreadCount = max(unreadCount - 1, 0)
        onChange?()

        do {
            try await api.markAsRead(id: notification.id)
            AppLogger.debug("Notification \(notification.id) marked as read")
            return nil
        } catch {
            locallyReadIDs.remove(notification.id)
            notifications.insert(notificationCopy, at: 0)
            unreadCount += 1
            onChange?()
            AppLogger.error("Failed to mark notification as read: \(error.localizedDescription)")
            return NetworkError(error)
        }
    }

    private func resolveCurrentUserIDIfNeeded() async {
        guard currentUserId == nil else { return }
        do {
            currentUserId = try await api.fetchCurrentUserId()
            AppLogger.debug("Resolved currentUserId: \(currentUserId ?? "nil")")
        } catch {
            AppLogger.warning("Failed to resolve currentUserId: \(error.localizedDescription)")
        }
    }

    private func startTasksRefreshTask() -> Task<[MegaplanTask]?, Never> {
        let userIdForTasks = currentUserId
        let sortKey = taskSortKey
        let statusFilter = taskStatusFilter
        return Task<[MegaplanTask]?, Never> { [weak self] in
            guard let self, let uid = userIdForTasks, !uid.isEmpty else { return nil }
            await MainActor.run {
                self.isTasksLoading = true
                self.onChange?()
            }
            defer {
                Task { @MainActor in
                    self.isTasksLoading = false
                    self.onChange?()
                }
            }
            do {
                return try await self.api.fetchTasks(
                    currentUserId: uid,
                    sortBy: sortKey,
                    statusFilter: statusFilter,
                    limit: 100
                )
            } catch {
                AppLogger.warning("fetchTasks failed: \(error.localizedDescription)")
                return nil
            }
        }
    }

    private func refreshNotificationsWithRetry() async throws -> ([MegaplanNotification], Int) {
        try await executeWithRetry {
            async let notificationsTask = self.api.fetchNotifications()
            async let counterTask = self.api.fetchUnreadCount()
            return try await (notificationsTask, counterTask)
        }
    }

    private func executeWithRetry<T>(_ operation: () async throws -> T) async throws -> T {
        var lastError: Error?

        for attempt in 1...maxRetries {
            do {
                return try await operation()
            } catch {
                lastError = error

                if shouldNotRetry(error) {
                    throw error
                }

                if attempt >= maxRetries {
                    break
                }

                let delay = min(baseDelay * pow(2.0, Double(attempt - 1)), maxDelay)
                AppLogger.info("Retrying refresh after \(delay)s (attempt \(attempt))")
                try await sleep(delay)
            }
        }

        if let error = lastError {
            AppLogger.error("All retry attempts failed: \(error.localizedDescription)")
            throw error
        }

        throw NetworkError.server(message: "Unknown error")
    }

    /// Не повторяем unauthorized, validationFailed и tooManyAttempts.
    private func shouldNotRetry(_ error: Error) -> Bool {
        if let networkError = error as? NetworkError {
            switch networkError {
            case .unauthorized, .validationFailed, .tooManyAttempts:
                return true
            default:
                break
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .badURL, .unsupportedURL, .cannotFindHost, .cannotConnectToHost:
                return false
            case .userCancelledAuthentication, .userAuthenticationRequired:
                return true
            default:
                return false
            }
        }

        return false
    }

    private func applySuccessfulRefresh(
        notifications fetchedNotifications: [MegaplanNotification],
        unreadCounter counter: Int
    ) async {
        isOffline = false
        isSessionExpired = false
        lastSyncTime = now()

        let fetchedIDs = Set(fetchedNotifications.map(\.id))
        locallyReadIDs.formIntersection(fetchedIDs)
        let visibleNotifications = fetchedNotifications.filter { !locallyReadIDs.contains($0.id) }
        let hiddenUnread = fetchedNotifications.reduce(into: 0) { count, item in
            if locallyReadIDs.contains(item.id), !item.isRead {
                count += 1
            }
        }
        let visibleUnread = max(counter - hiddenUnread, 0)

        let previousNotificationIDs = Set(notifications.map(\.id))
        let newUnreadNotifications = visibleNotifications.filter {
            !previousNotificationIDs.contains($0.id) && !$0.isRead
        }
        for notification in newUnreadNotifications {
            poster.send(notification)
        }

        lastSuccessfulNotifications = visibleNotifications
        lastSuccessfulUnreadCount = visibleUnread
        if let workspaceKey = AppState.workspaceKey(from: domain) {
            await snapshotStore.save(
                workspaceKey: workspaceKey,
                unreadCount: visibleUnread,
                notifications: visibleNotifications
            )
        }

        notifications = visibleNotifications
        unreadCount = visibleUnread
        AppLogger.debug("Refreshed: \(visibleNotifications.count) notifications, \(visibleUnread) unread, \(newUnreadNotifications.count) new unread")
    }

    private func applyTasksResult(from task: Task<[MegaplanTask]?, Never>) async {
        guard let fetchedTasks = await task.value else { return }
        tasks = fetchedTasks
        tasksUnreadCount = fetchedTasks.reduce(0) { $0 + $1.unreadCommentsCount }
        lastTasksSyncTime = now()
        AppLogger.debug("Refreshed: \(fetchedTasks.count) tasks, \(tasksUnreadCount) unread comments")
    }

    private func restoreCachedNotifications() {
        guard !lastSuccessfulNotifications.isEmpty else { return }
        notifications = lastSuccessfulNotifications
        unreadCount = lastSuccessfulUnreadCount
        AppLogger.debug("Using cached data in offline mode (total: \(lastSuccessfulNotifications.count))")
    }

    private func isTransientNetworkFailure(_ error: NetworkError) -> Bool {
        switch error {
        case .offline, .timedOut:
            return true
        default:
            return false
        }
    }
}
