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
    var isAuthenticated: Bool {
        get { session.isAuthenticated }
        set { commitAuthenticated(newValue) }
    }
    #else
    @Published private(set) var notifications: [MegaplanNotification] = []
    private(set) var isAuthenticated: Bool {
        get { session.isAuthenticated }
        set { commitAuthenticated(newValue) }
    }
    #endif
    @Published private(set) var unreadCount: Int = 0
    @Published var firstName: String = ""
    @Published private(set) var apiUnreadCount: Int = 0
    @Published var isAdmin: Bool = false
    @Published private(set) var isLoading: Bool = false
    /// True while sign-in is in flight. Feed refresh keeps using `isLoading`.
    var isSigningIn: Bool { session.isSigningIn }
    @Published var isOffline: Bool = false
    @Published private(set) var isSessionExpired: Bool = false
    @Published private(set) var lastSyncTime: Date?
    @Published var alertItem: AlertItem?
    var lockoutState: LockoutState? { session.lockoutState }
    /// Not private(set): AuthView clears this when the user edits a field, so a binding-friendly setter is required.
    var lastAuthError: AuthFieldError? {
        get { session.lastAuthError }
        set { session.lastAuthError = newValue }
    }
    /// Transient banner message shown briefly in the popover (e.g. "comments
    /// copied"). Auto-clears on its own; nil hides the banner.
    @Published var transientToast: String?
    @Published var certificatePinningFailed: Bool = false
    @Published var domain: String {
        didSet { sync.domain = domain }
    }
    @Published var username: String
    @Published private(set) var refreshInterval: Double
    @Published private(set) var autoLaunchEnabled: Bool
    @Published var tempCredentials: MegaplanCredentials

    // MARK: - Tasks tab state
    @Published private(set) var tasks: [MegaplanTask] = []
    @Published private(set) var isTasksLoading: Bool = false
    @Published private(set) var taskSortKey: TaskSortKey = .activity {
        didSet { sync.taskSortKey = taskSortKey }
    }
    @Published private(set) var taskStatusFilter: TaskStatusFilter = .active {
        didSet { sync.taskStatusFilter = taskStatusFilter }
    }
    @Published private(set) var lastTasksSyncTime: Date?
    @Published private(set) var tasksUnreadCount: Int = 0

    // MARK: - Settings UI helpers

    /// Human-readable representation of the last successful notifications sync,
    /// suitable for AccountCard. Returns nil when no sync has occurred yet.
    var formattedLastSync: String? {
        guard let lastSyncTime else { return nil }
        return DateFormatters.relative(lastSyncTime)
    }

    /// Cached avatar of the currently signed-in user.
    @Published private(set) var currentUserAvatar: NSImage?

    var api: MegaplanAPI
    /// Домен и токен, уже записанные в `api`. nil — клиент ещё не пересоздавали.
    var installedDomain: String?
    private var installedToken: String?
    private var resolverConfiguration: Task<Void, Never>?
    /// Вход и токен. Лента и таймер остаются здесь.
    private let session: SessionGate
    let userDefaults: UserDefaults
    let snapshotStore: NotificationsSnapshotStore
    let sync: WorkspaceSync
    private let refreshScheduler: RefreshScheduler
    private var refreshTask: Task<Void, Never>?
    private var certificatePinningObserver: (any NSObjectProtocol)?
    private var lastRefreshTime: Date?
    private let minimumRefreshInterval: TimeInterval = 5.0
    var isShuttingDown = false

    init(
        api: MegaplanAPI = MegaplanAPI(),
        userDefaults: UserDefaults = .standard,
        snapshotStore: NotificationsSnapshotStore = .shared,
        keychain: KeychainStoring = KeychainManager()
    ) {
        self.api = api
        self.userDefaults = userDefaults
        self.snapshotStore = snapshotStore
        self.session = SessionGate(keychain: keychain)
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
        self.sync = WorkspaceSync(
            api: api,
            snapshotStore: snapshotStore,
            poster: NotificationManagerPoster()
        )
        sync.domain = domainValue
        sync.taskSortKey = taskSortKey
        sync.taskStatusFilter = taskStatusFilter
        sync.onChange = { [weak self] in
            self?.publishSyncedFeed()
        }
        session.attach(self)

        // Стартовый домен из UserDefaults — отдельный клиент, не мутация.
        if !domainValue.isEmpty {
            installAPI(domain: domainValue, token: nil)
        } else {
            bindResolver(to: api)
        }
        
        // Синхронизация unreadCount с счётчиком из API
        $apiUnreadCount
            .assign(to: &$unreadCount)

        // Хост модульных тестов не должен трогать разрешения, Keychain и сеть.
        if !LaunchContext.isUnitTestHost {
            Task {
                _ = await NotificationManager.shared.requestAuthorization()
            }
        }

        // Subscribe to certificate pinning failure notifications.
        // Сохраняем токен наблюдателя, чтобы корректно снять подписку в deinit.
        // Closure доставляется на main queue → используем assumeIsolated для @MainActor мутаций.
        if !LaunchContext.isUnitTestHost {
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
                await self?.session.restoreSession()
            }
        }
    }

    func signIn(domain: String, login: String, password: String) async {
        await session.signIn(domain: domain, login: login, password: password)
    }

    func logout() {
        session.logout()
    }

    // MARK: - Admin diagnostics (Settings → About → Quick links)

    /// Copies the API diagnostic log to the system pasteboard.
    func copyLogToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(WorkspaceAddress.diagnosticText(), forType: .string)
    }

    /// Workspace knowledge base. Nil when the domain is empty or not a host.
    var knowledgeBaseURL: URL? {
        WorkspaceAddress.page(.knowledge, domain: domain)
    }

    /// Workspace deals list. Nil when the domain is empty or not a host.
    var dealsURL: URL? {
        WorkspaceAddress.page(.deals, domain: domain)
    }

    /// Workspace task list. Nil when the domain is empty or not a host.
    var tasksURL: URL? {
        WorkspaceAddress.page(.tasks, domain: domain)
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
            await refreshScheduler.updateInterval(clampedInterval, action: scheduledRefreshAction())
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
        guard session.token != nil else {
            showTransientToast(String(localized: "tasks.markdown.failed"))
            return nil
        }
        do {
            let bundle = try await api.fetchTaskComments(taskId: task.id)
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
        guard session.token != nil,
              let userId = sync.currentUserId,
              !userId.isEmpty,
              !trimmed.isEmpty else {
            return []
        }
        do {
            return try await api.searchTasks(currentUserId: userId,
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
        guard session.token != nil else {
            presentError(.missingToken)
            return
        }

        Task { [weak self] in
            guard let self else { return }
            if let error = await self.sync.markNotificationAsRead(notification) {
                self.presentError(error)
            }
        }
    }

    /// Returns the password saved for (domain, login) if it matches the
    /// currently-stored credentials, otherwise nil. Used by AuthView wizard
    /// to restore the password field when the user returns to Step 2.
    func loadSavedCredentialsFromKeychain(domain: String, login: String) async -> String? {
        await session.loadSavedCredentialsFromKeychain(domain: domain, login: login)
    }

    func refresh() async {
        guard !Task.isCancelled else { return }
        guard session.token != nil else {
            AppLogger.debug("Refresh called but no access token")
            return
        }

        isLoading = true
        defer { isLoading = false }
        await sync.refresh()
        finishSyncRefresh()
    }

    private func setFeedLoading(_ loading: Bool) {
        isLoading = loading
    }

    /// 401 гасит таймер здесь: таймер живёт в AppState, его действие зовёт `sync.refresh()`.
    /// Токен обнуляется на gate, второго флага сессии на AppState нет.
    private func finishSyncRefresh() {
        publishSyncedFeed()
        if sync.isSessionExpired {
            session.token = nil
            isAuthenticated = false
            stopRefreshTimer()
        }
        if let alert = sync.takePendingAlert() {
            presentError(alert)
        }
    }

    private func scheduledRefreshAction() -> @Sendable () async -> Void {
        { [weak self] in
            guard let self else { return }
            // Требуется await для доступа к @MainActor свойству из actor контекста
            if await self.isShuttingDown { return }
            guard await self.session.token != nil else { return }
            await self.setFeedLoading(true)
            await self.sync.refresh()
            await self.finishSyncRefresh()
            await self.setFeedLoading(false)
        }
    }

    /// Единственная запись флага сессии: хранилище на gate, зеркало на sync.
    func commitAuthenticated(_ value: Bool) {
        objectWillChange.send()
        session.setStoredAuthenticated(value)
        sync.isAuthenticated = value
    }

    func publishSyncedFeed() {
        withAnimation(.easeInOut) {
            notifications = sync.notifications
            tasks = sync.tasks
            unreadCount = sync.unreadCount
            isOffline = sync.isOffline
            isSessionExpired = sync.isSessionExpired
            lastSyncTime = sync.lastSyncTime
            tasksUnreadCount = sync.tasksUnreadCount
            lastTasksSyncTime = sync.lastTasksSyncTime
            isTasksLoading = sync.isTasksLoading
            isAuthenticated = sync.isAuthenticated
        }
        apiUnreadCount = sync.unreadCount
    }

    func startRefreshTimer() {
        guard isAuthenticated, !isShuttingDown else { return }

        Task {
            await refreshScheduler.start(interval: refreshInterval, action: scheduledRefreshAction())
        }
    }

    func stopRefreshTimer() {
        Task {
            await refreshScheduler.stop()
        }
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Пересоздаёт клиент, только если домен или токен реально другие.
    /// Подменённая сессия (мок в тестах) переносится через `withCredentials`.
    func installAPI(domain: String, token: String?) {
        let normalized = Self.normalizedAPIToken(token)
        if installedDomain == domain, installedToken == normalized {
            return
        }
        installedDomain = domain
        installedToken = normalized
        let next = api.withCredentials(domain: domain, token: normalized)
        api = next
        sync.updateAPI(next)
        bindResolver(to: next)
    }

    private func bindResolver(to client: MegaplanAPI) {
        let previous = resolverConfiguration
        resolverConfiguration = Task { [weak self] in
            await previous?.value
            await UserInfoResolver.shared.configure(
                api: client,
                tokenProvider: { [weak self] in
                    await self?.session.token
                },
                domainProvider: { [weak self] in
                    await self?.domain ?? ""
                }
            )
        }
    }

    private static func normalizedAPIToken(_ token: String?) -> String? {
        guard let token, !token.isEmpty else { return nil }
        return token
    }

    func applyTokenValidationResult(_ result: (isValid: Bool, firstName: String?, unreadCount: Int?, possibleActions: [String]?)) {
        if let firstName = result.firstName {
            self.firstName = firstName
        }
        if let unreadCount = result.unreadCount {
            self.apiUnreadCount = unreadCount
        }
        self.isAdmin = Constants.AdminPermissions.isAdministrator(result.possibleActions)
    }

    func restoreSnapshotIfAvailable(for domain: String) async {
        sync.domain = domain
        await sync.restoreSnapshotIfAvailable()
        publishSyncedFeed()
    }

    static func workspaceKey(from domain: String) -> String? {
        let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let hasScheme = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
        let normalized = hasScheme ? trimmed : "https://\(trimmed)"
        return URL(string: normalized)?.host?.lowercased()
    }

    func presentError(_ error: NetworkError) {
        alertItem = AlertItem(message: error.localizedDescription)
    }

    func isTransientNetworkFailure(_ error: NetworkError) -> Bool {
        switch error {
        case .offline, .timedOut:
            return true
        default:
            return false
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
