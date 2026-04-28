import Combine
import Foundation
import SwiftUI

@MainActor
final class NotificationListViewModel: ObservableObject {
    struct NotificationTypeFilterOption: Identifiable, Equatable {
        var id: String { typeKey }
        let typeKey: String
        let title: String

        var isUntyped: Bool { typeKey.isEmpty }
    }

    @Published var notifications: [MegaplanNotification] = []
    @Published var groupedNotifications: [NotificationGroup] = []
    @Published var errorMessage: String?
    @Published var groupingEnabled: Bool = true
    @Published var showOnlyUnread: Bool = false
    @Published var searchQuery: String = ""
    @Published var isSearchActive: Bool = false
    @Published var isFilterPanelActive: Bool = false
    @Published private(set) var typeFilterOptions: [NotificationTypeFilterOption] = []
    @Published var selectedTypeFilterKeys: Set<String> = []

    let appState: AppState
    private let userDefaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()
    private var lastSuccessfulNotifications: [MegaplanNotification] = []
    private var visitedNotificationIds: Set<String> = []
    private var searchableNotifications: [SearchableNotification] = []
    
    init(appState: AppState, userDefaults: UserDefaults = .standard) {
        self.appState = appState
        self.userDefaults = userDefaults
        
        // Загружаем настройки
        groupingEnabled = userDefaults.object(forKey: Constants.UserDefaultsKeys.groupingEnabled) as? Bool ?? true
        showOnlyUnread = userDefaults.bool(forKey: Constants.UserDefaultsKeys.showOnlyUnread)
        
        // Загружаем список посещенных уведомлений
        if let visitedIds = userDefaults.array(forKey: Constants.UserDefaultsKeys.visitedNotificationIds) as? [String] {
            visitedNotificationIds = Set(visitedIds)
        }
        
        // Подписываемся на изменения уведомлений из AppState
        appState.$notifications
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newNotifications in
                self?.notifications = newNotifications
                // Создаем searchable версии для оптимизированного поиска
                self?.searchableNotifications = newNotifications.map { SearchableNotification(notification: $0) }
                self?.updateGroupedNotifications()
            }
            .store(in: &cancellables)
        
        // Subscribe to search query changes with debounce for performance
        $searchQuery
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateGroupedNotifications()
            }
            .store(in: &cancellables)
        
        // Инициализируем группировку
        updateGroupedNotifications()
    }
    
    func refresh() async {
        await appState.refresh()
    }
    
    func markAsRead(_ notification: MegaplanNotification) {
        appState.markNotificationAsRead(notification)
    }
    
    func updateGroupedNotifications() {
        let baseNotifications = baseNotifications()
        typeFilterOptions = buildTypeFilterOptions(from: baseNotifications)
        selectedTypeFilterKeys = normalizedSelection(from: selectedTypeFilterKeys, availableOptions: typeFilterOptions)

        var filteredNotifications = baseNotifications
        
        if !selectedTypeFilterKeys.isEmpty {
            filteredNotifications = filteredNotifications.filter {
                selectedTypeFilterKeys.contains(Self.normalizedTypeKey($0.type))
            }
        }
        
        // Фильтруем по поисковому запросу, если он активен и содержит минимум 2 символа
        if isSearchActive && searchQuery.count >= 2 {
            filteredNotifications = filterNotifications(filteredNotifications, query: searchQuery)
        }
        
        // Группируем, если включена настройка
        if groupingEnabled {
            groupedNotifications = NotificationGrouper.group(filteredNotifications)
        } else {
            // Если группировка отключена, создаем одну группу со всеми уведомлениями
            groupedNotifications = [NotificationGroup(
                id: "all",
                title: "",
                notifications: filteredNotifications,
                date: Date()
            )]
        }
    }
    
    func updateGroupingEnabled(_ enabled: Bool) {
        groupingEnabled = enabled
        userDefaults.set(enabled, forKey: Constants.UserDefaultsKeys.groupingEnabled)
        updateGroupedNotifications()
    }
    
    func updateShowOnlyUnread(_ enabled: Bool) {
        showOnlyUnread = enabled
        userDefaults.set(enabled, forKey: Constants.UserDefaultsKeys.showOnlyUnread)
        updateGroupedNotifications()
    }
    
    /// Проверяет, было ли уведомление посещено
    func isVisited(_ notification: MegaplanNotification) -> Bool {
        visitedNotificationIds.contains(notification.id)
    }
    
    /// Помечает уведомление как посещенное
    func markAsVisited(_ notification: MegaplanNotification) {
        visitedNotificationIds.insert(notification.id)
        saveVisitedIds()
    }
    
    /// Сохраняет список посещенных уведомлений в UserDefaults
    private func saveVisitedIds() {
        userDefaults.set(Array(visitedNotificationIds), forKey: Constants.UserDefaultsKeys.visitedNotificationIds)
    }
    
    /// Обновляет поисковый запрос и применяет фильтрацию
    func updateSearchQuery(_ query: String) {
        searchQuery = query
    }
    
    /// Очищает поисковый запрос (поиск остается активным)
    func clearSearch() {
        searchQuery = ""
    }
    
    /// Возвращает количество найденных уведомлений при активном поиске
    var searchResultsCount: Int {
        guard isSearchActive && searchQuery.count >= 2 else {
            return filteredNotificationsCount
        }
        let filtered = filteredNotificationsForSearch()
        return filterNotifications(filtered, query: searchQuery).count
    }

    var filteredNotificationsCount: Int {
        filteredNotificationsForSearch().count
    }

    /// Фильтрует уведомления по поисковому запросу
    /// Использует предварительно обработанный searchText для оптимизации
    private func filterNotifications(_ notifications: [MegaplanNotification], query: String) -> [MegaplanNotification] {
        let lowercasedQuery = query.lowercased()

        // Используем searchableNotifications для оптимизированного поиска
        var matchedIds = Set<String>()

        for searchable in searchableNotifications where searchable.matches(query: lowercasedQuery) {
            matchedIds.insert(searchable.notification.id)
        }

        // Возвращаем отфильтрованные уведомления в исходном порядке
        return notifications.filter { matchedIds.contains($0.id) }
    }

    private func filteredNotificationsForSearch() -> [MegaplanNotification] {
        var filtered = baseNotifications()
        if !selectedTypeFilterKeys.isEmpty {
            filtered = filtered.filter { selectedTypeFilterKeys.contains(Self.normalizedTypeKey($0.type)) }
        }
        return filtered
    }

    private func baseNotifications() -> [MegaplanNotification] {
        if showOnlyUnread {
            return notifications.filter { !$0.isRead }
        }
        return notifications
    }

    private func buildTypeFilterOptions(from notifications: [MegaplanNotification]) -> [NotificationTypeFilterOption] {
        let typeKeys = Set(notifications.map { Self.normalizedTypeKey($0.type) })
        return typeKeys.map { key in
            NotificationTypeFilterOption(
                typeKey: key,
                title: NotificationEventTypeCatalog.title(for: key.isEmpty ? nil : key)
            )
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func normalizedSelection(from current: Set<String>, availableOptions: [NotificationTypeFilterOption]) -> Set<String> {
        let availableKeys = Set(availableOptions.map(\.typeKey))
        return current.intersection(availableKeys)
    }

    private static func normalizedTypeKey(_ rawType: String?) -> String {
        guard let rawType else { return "" }
        let trimmed = rawType.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed
    }
}

enum NotificationEventTypeCatalog {
    static let russianNames: [String: String] = [
        "BumsSettingsN_BackupCompleted": "BumsSettingsN_BackupCompleted",
        "BumsCommonN_CommentLiked": "Ваш комментарий понравился пользователю",
        "BumsTaskN_NegotiationItemVisaCompleted": "Все приняли решение",
        "BumsStaffN_Invite": "Вы добавили сотрудника",
        "BumsTradeN_DealAddAuditors": "Вы добавлены в сделку аудитором",
        "BumsTradeN_DealAddRole": "Вы добавлены в сделку в другой роли",
        "BumsTradeN_DealAddManager": "Вы добавлены в сделку менеджером",
        "BumsTaskN_TaskRemoveExecutor": "Вы исключены из исполнителей задачи",
        "BumsAlienN_ContractorYouAddedToResponsibles": "Вы назначены ответственным по клиенту",
        "BumsAlienN_ContractorYouRemovedFromResponsibles": "Вы удалены из ответственных по клиенту",
        "BumsTaskN_DeadlineChange": "Дедлайн по задаче был изменен",
        "BumsDocN_NewDocument": "Добавлен новый документ",
        "BumsTaskN_NewNegotiationItemVisa": "Документ согласован",
        "BumsTaskN_TaskResumed": "Задача возобновлена",
        "BumsTaskN_TaskDelegated": "Задача делегирована",
        "BumsTaskN_TaskDone": "Задача завершена",
        "BumsTaskN_TaskCompleted": "Задача закрыта",
        "BumsTaskN_TaskRejected": "Задача отклонена",
        "BumsTaskN_TaskAccepted": "Задача принята",
        "BumsTaskN_TaskPaused": "Задача приостановлена",
        "BumsTaskN_TaskExpired": "Задача провалена",
        "BumsTaskN_TaskReopened": "Задача снова открыта",
        "BumsTaskN_TaskCanceled": "Задача снята",
        "BumsTaskN_TaskDeleted": "Задача удалена",
        "BumsTaskN_NegotiationTaskAccepted": "Задача-согласование принята к исполнению",
        "BumsTaskN_DeadlineChangeCreate": "Запросы на изменение дедлайна задачи",
        "bums\\integration\\forms\\n\\FormProcess": "Заявка из формы обратной связи",
        "BumsStaffN_VacationCreated": "Заявка на отпуск",
        "BumsStaffN_VacationApproved": "Заявка на отпуск утверждена",
        "BumsImportN_InformerProcessNotification": "Импорт",
        "bums\\common\\common\\api\\v03\\Notification\\MassActionsProcessFinished": "Массовое действие завершено",
        "BumsCommonN_ExactTimeLocalReminder": "Напоминание",
        "BumsStaffN_Birthday": "Напоминание о дне рождения",
        "BumsAlienN_Birthday": "Напоминание о дне рождения/основания клиента",
        "BumsTaskN_DeadlineComing": "Напоминание о приближающемся дедлайне по задаче",
        "BumsItemN_Reminder": "Напоминание о событии",
        "BumsTaskN_TaskAddAuditor": "Новая аудируемая задача",
        "BumsDocN_NewVersion": "Новая версия документа",
        "BumsTaskN_NewNegotiationItemVersion": "Новая версия документа для согласования",
        "BumsDiscussN_MessageCreated": "Новое личное письмо",
        "BumsDiscussN_VisavisNewComment": "Новое личное сообщение",
        "BumsDiscussN_ContractorMessageCreated": "Новое письмо от клиента",
        "BumsProjectN_ProjectNewAuditor": "Новый аудируемый проект",
        "BumsAlienN_ContractorNewDuplicate": "Новый дублер вашего клиента",
        "BumsDocN_DocNewComment": "Новый комментарий к документу",
        "BumsDiscussN_ChatNewComment": "Новый комментарий от клиента",
        "BumsTaskN_TaskNewComment": "Новый комментарий по задаче",
        "BumsAlienN_ContractorNewComment": "Новый комментарий по клиенту",
        "BumsItemN_NewComment": "Новый комментарий по коммуникации",
        "BumsDiscussN_EmailNewComment": "Новый комментарий по обсуждению",
        "BumsDiscussN_TopicNewComment": "Новый комментарий по обсуждению",
        "BumsProjectN_ProjectNewComment": "Новый комментарий по проекту",
        "BumsTradeN_DealNewComment": "Новый комментарий по сделке",
        "BumsItemN_ParticipantReject": "Отказ от участия",
        "BumsTradeN_DealScenarioNotification": "Отправлено уведомление через сценарий",
        "BumsDiscussN_ChatCreated": "Переписка с клиентом",
        "BumsItemN_ResultLetter": "Письмо с результатом коммуникации",
        "BumsKnowledgeN_KnowledgeAddAccess": "Получено право доступа к базе знаний или статье",
        "BumsTaskN_FirstUserInviteTask": "Посмотрите задачу",
        "BumsProjectN_ProjectReopened": "Проект возобновлён",
        "BumsProjectN_ProjectDone": "Проект завершен",
        "BumsProjectN_ProjectCompleted": "Проект закрыт",
        "BumsProjectN_ProjectCancelled": "Проект снят",
        "BumsTradeN_DealChanged": "Сделка была изменена",
        "BumsDiscussN_TopicCreated": "Создано новое обсуждение",
        "BumsProjectN_ProjectAssigned": "Сотрудник добавил менеджера в проект",
        "BumsTaskN_TaskModifyResponsible": "Сотрудник добавил ответственного в задачу",
        "BumsTaskN_TaskModifyOwner": "Сотрудник добавил постановщика в задачу",
        "BumsProjectN_ProjectModifyOwner": "Сотрудник добавил постановщика в проект",
        "BumsTaskN_TaskAddExecutor": "Сотрудник добавил соисполнителя в задачу",
        "BumsItemN_ParticipantsAdded": "Сотрудник запланировал событие",
        "BumsTradeN_DealStatusChanged": "Статус сделки изменился",
        "BumsItemN_TimeModified": "Уведомление об изменении времени события",
        "BumsCommonN_SimpleNotification": "Уведомление об ошибке",
        "BumsReportN_ReportDone": "Уведомления о готовности отчётов",
        "BumsCommonN_FilterChange": "Уведомления об изменениях в фильтрах",
        "BumsCommonN_ChecklistChanges": "Уведомления об изменениях в чек-листе",
        "BumsCommonN_NewFile": "Экспорт",
        "bums\\common\\common\\api\\v03\\Notification\\ExportStarted": "Экспорт фильтров"
    ]

    static func title(for rawType: String?) -> String {
        guard let rawType, !rawType.isEmpty else {
            return String(localized: "notifications.filter.type.untyped")
        }
        return russianNames[rawType] ?? rawType
    }
}

