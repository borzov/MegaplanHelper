import Foundation

// MARK: - Notification Type Classification

/// Категория уведомления по модулю системы Мегаплан.
///
/// Категории определяются префиксом типа уведомления:
/// - `BumsTaskN` - уведомления по задачам
/// - `BumsTradeN` - уведомления по сделкам
/// - `BumsItemN` - общие события и дела
///
/// Пример использования:
/// ```swift
/// let category = notification.category
/// let taskNotifications = notifications.filtered(by: .task)
/// ```
enum NotificationCategory: String {
    case task = "BumsTaskN"
    case deal = "BumsTradeN"
    case item = "BumsItemN"
    case unknown = "unknown"
    
    var displayName: String {
        switch self {
        case .task: return "Задачи"
        case .deal: return "Сделки"
        case .item: return "События"
        case .unknown: return "Прочее"
        }
    }
}

/// Конкретный тип уведомления в системе Мегаплан.
///
/// Типы уведомлений определены на основе анализа API ответов системы Мегаплан.
/// Каждый тип имеет уникальный строковый идентификатор, который используется для
/// программной идентификации типа события.
///
/// Пример использования:
/// ```swift
/// let type = notification.notificationType
/// if type == .taskNewComment {
///     // Обработка комментария в задаче
/// }
/// let commentNotifications = notifications.comments
/// let systemNotifications = notifications.systemNotifications
/// ```
enum NotificationType: String, CaseIterable {
    // Задачи
    case taskNewComment = "BumsTaskN_TaskNewComment"
    case taskAddAuditor = "BumsTaskN_TaskAddAuditor"
    
    // Сделки
    case dealNewComment = "BumsTradeN_DealNewComment"
    case dealAddAuditors = "BumsTradeN_DealAddAuditors"
    case dealAddRole = "BumsTradeN_DealAddRole"
    case dealStatusChanged = "BumsTradeN_DealStatusChanged"
    case dealScenarioNotification = "BumsTradeN_DealScenarioNotification"
    
    // Общие события
    case participantsAdded = "BumsItemN_ParticipantsAdded"
    
    case unknown = "unknown"
    
    /// Определяет тип уведомления из строки
    static func from(_ typeString: String?) -> NotificationType {
        guard let typeString = typeString, !typeString.isEmpty else {
            return .unknown
        }
        
        return allCases.first { $0.rawValue == typeString } ?? .unknown
    }
    
    /// Определяет категорию уведомления из строки типа
    static func category(from typeString: String?) -> NotificationCategory {
        guard let typeString = typeString, !typeString.isEmpty else {
            return .unknown
        }
        
        if typeString.hasPrefix("BumsTaskN") {
            return .task
        } else if typeString.hasPrefix("BumsTradeN") {
            return .deal
        } else if typeString.hasPrefix("BumsItemN") {
            return .item
        }
        
        return .unknown
    }
    
    /// Человекочитаемое описание типа
    var description: String {
        switch self {
        case .taskNewComment:
            return "Новый комментарий в задаче"
        case .taskAddAuditor:
            return "Добавление аудитора в задачу"
        case .dealNewComment:
            return "Новый комментарий в сделке"
        case .dealAddAuditors:
            return "Добавление аудитора в сделку"
        case .dealAddRole:
            return "Добавление роли в сделке"
        case .dealStatusChanged:
            return "Смена статуса сделки"
        case .dealScenarioNotification:
            return "Системное уведомление по сделке"
        case .participantsAdded:
            return "Добавление участника в событие"
        case .unknown:
            return "Неизвестное уведомление"
        }
    }
    
    /// Иконка для типа уведомления
    var icon: String {
        switch self {
        case .taskNewComment, .dealNewComment:
            return "bubble.left"
        case .taskAddAuditor, .dealAddAuditors, .dealAddRole, .participantsAdded:
            return "person.badge.plus"
        case .dealStatusChanged:
            return "arrow.triangle.2.circlepath"
        case .dealScenarioNotification:
            return "gearshape"
        case .unknown:
            return "bell"
        }
    }
    
    /// Является ли уведомление системным (от системы, а не от пользователя)
    var isSystem: Bool {
        switch self {
        case .dealScenarioNotification:
            return true
        default:
            return false
        }
    }
    
    /// Относится ли уведомление к комментариям
    var isComment: Bool {
        switch self {
        case .taskNewComment, .dealNewComment:
            return true
        default:
            return false
        }
    }
    
    /// Относится ли уведомление к изменениям статуса
    var isStatusChange: Bool {
        switch self {
        case .dealStatusChanged:
            return true
        default:
            return false
        }
    }
}

struct MegaplanNotification: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let body: String
    let createdAt: Date
    let link: URL?
    let isRead: Bool
    let isMention: Bool
    let unreadCommentsCount: Int
    let size: Int
    let type: String?
    let senderName: String?
    let senderAvatarURL: URL?
    let senderId: String?
    
    /// Определенный тип уведомления
    var notificationType: NotificationType {
        NotificationType.from(type)
    }
    
    /// Категория уведомления
    var category: NotificationCategory {
        NotificationType.category(from: type)
    }
    
    /// Иконка для уведомления на основе его типа
    var notificationIcon: String {
        notificationType.icon
    }
    
    /// Является ли уведомление системным
    var isSystemNotification: Bool {
        notificationType.isSystem
    }
    
    /// Относится ли уведомление к комментариям
    var isCommentNotification: Bool {
        notificationType.isComment
    }
    
    /// Относится ли уведомление к изменению статуса
    var isStatusChangeNotification: Bool {
        notificationType.isStatusChange
    }

    var displayDate: String {
        Self.formatRelativeDate(createdAt)
    }

    // MARK: - Cached Date Formatters

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "в HH:mm"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "d MMMM"
        return formatter
    }()

    private static let calendar = Calendar.current

    private static func formatRelativeDate(_ date: Date) -> String {
        let calendar = Self.calendar

        if calendar.isDateInToday(date) {
            return "сегодня \(timeFormatter.string(from: date))"
        } else if calendar.isDateInYesterday(date) {
            return "вчера \(timeFormatter.string(from: date))"
        } else {
            return "\(dayFormatter.string(from: date)) \(timeFormatter.string(from: date))"
        }
    }

    init(id: String, title: String, body: String, createdAt: Date, link: URL?, isRead: Bool, isMention: Bool = false, unreadCommentsCount: Int = 0, size: Int = 0, type: String? = nil, senderName: String? = nil, senderAvatarURL: URL? = nil, senderId: String? = nil) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.link = link
        self.isRead = isRead
        self.isMention = isMention
        self.unreadCommentsCount = unreadCommentsCount
        self.size = size
        self.type = type
        self.senderName = senderName
        self.senderAvatarURL = senderAvatarURL
        self.senderId = senderId
    }
}

extension MegaplanNotification {
    static let previewSample = MegaplanNotification(
        id: UUID().uuidString,
        title: "Новая задача",
        body: "Вам назначена новая задача в Megaplan.",
        createdAt: Date(),
        link: URL(string: "https://demo.megaplan.ru"),
        isRead: false,
        isMention: true,
        unreadCommentsCount: 3,
        type: "BumsTaskN_TaskNewComment",
        senderName: "Гусев Максим",
        senderAvatarURL: nil,
        senderId: "1000056"
    )
}

// MARK: - Collection Extensions for Notifications

extension Array where Element == MegaplanNotification {
    /// Фильтрует уведомления по категории
    func filtered(by category: NotificationCategory) -> [MegaplanNotification] {
        filter { $0.category == category }
    }
    
    /// Фильтрует уведомления по типу
    func filtered(by type: NotificationType) -> [MegaplanNotification] {
        filter { $0.notificationType == type }
    }
    
    /// Фильтрует только комментарии
    var comments: [MegaplanNotification] {
        filter { $0.isCommentNotification }
    }
    
    /// Фильтрует только системные уведомления
    var systemNotifications: [MegaplanNotification] {
        filter { $0.isSystemNotification }
    }
    
    /// Фильтрует только уведомления об изменении статуса
    var statusChanges: [MegaplanNotification] {
        filter { $0.isStatusChangeNotification }
    }
    
    /// Группирует уведомления по категориям
    func groupedByCategory() -> [NotificationCategory: [MegaplanNotification]] {
        Dictionary(grouping: self) { $0.category }
    }
    
    /// Группирует уведомления по типам
    func groupedByType() -> [NotificationType: [MegaplanNotification]] {
        Dictionary(grouping: self) { $0.notificationType }
    }
}

// MARK: - Search Optimization

/// Wrapper для уведомления с предварительно обработанным поисковым текстом
/// Используется для оптимизации поиска - избегает повторных вызовов lowercased()
struct SearchableNotification {
    let notification: MegaplanNotification
    let searchText: String

    init(notification: MegaplanNotification) {
        self.notification = notification

        // Предварительно создаем lowercased текст для поиска
        var components: [String] = []

        if !notification.title.isEmpty {
            components.append(notification.title)
        }

        if !notification.body.isEmpty {
            components.append(notification.body)
        }

        if let senderName = notification.senderName, !senderName.isEmpty {
            components.append(senderName)
        }

        self.searchText = components.joined(separator: " ").lowercased()
    }

    /// Проверяет, содержит ли уведомление заданный поисковый запрос
    /// - Parameter query: Поисковый запрос (уже lowercased)
    /// - Returns: true если уведомление соответствует запросу
    func matches(query: String) -> Bool {
        return searchText.contains(query)
    }
}
