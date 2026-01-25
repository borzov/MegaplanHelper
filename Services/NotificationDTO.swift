import Foundation

// MARK: - DTOs

struct AuthEnvelope: Decodable {
    let accessToken: String?
    let expiresIn: Int?
    let tokenType: String?
    let scope: String?
    let refreshToken: String?
}

struct NotificationsEnvelope: Decodable {
    let items: [NotificationDTO]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)

        // Пробуем декодировать data массив напрямую
        if let dataKey = DynamicCodingKey(stringValue: "data") {
            if let dataArray = try? container.decode([NotificationDTO].self, forKey: dataKey) {
                self.items = dataArray
                return
            }
        }

        // Fallback на вложенную структуру
        if let dataKey = DynamicCodingKey(stringValue: "data"),
           let dataContainer = try? container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: dataKey) {
            self.items = NotificationsEnvelope.extractNotifications(from: dataContainer)
        } else {
            self.items = NotificationsEnvelope.extractNotifications(from: container)
        }
    }

    private static func extractNotifications(from container: KeyedDecodingContainer<DynamicCodingKey>) -> [NotificationDTO] {
        let candidateKeys = ["notifications", "list", "items"]
        for keyName in candidateKeys {
            guard let key = DynamicCodingKey(stringValue: keyName) else { continue }

            if let wrapped = try? container.decode([WrappedNotification].self, forKey: key) {
                return wrapped.map(\.notification)
            }

            if let direct = try? container.decode([NotificationDTO].self, forKey: key) {
                return direct
            }

            if let nestedContainer = try? container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: key) {
                let nested = extractNotifications(from: nestedContainer)
                if !nested.isEmpty {
                    return nested
                }
            }
        }

        return []
    }
}

struct CounterEnvelope: Decodable {
    let counter: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        if let dataKey = DynamicCodingKey(stringValue: "data"),
           let dataContainer = try? container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: dataKey) {
            if let countKey = DynamicCodingKey(stringValue: "count"),
               let countValue = try? dataContainer.decodeIfPresent(Int.self, forKey: countKey) {
                self.counter = countValue
                return
            }
            if let counterKey = DynamicCodingKey(stringValue: "counter"),
               let counterValue = try? dataContainer.decodeIfPresent(Int.self, forKey: counterKey) {
                self.counter = counterValue
                return
            }
        }

        if let counterKey = DynamicCodingKey(stringValue: "counter"),
           let value = try container.decodeIfPresent(Int.self, forKey: counterKey) {
            self.counter = value
            return
        }

        self.counter = 0
    }
}

struct WrappedNotification: Decodable {
    let notification: NotificationDTO
}

struct NotificationDTO: Decodable {
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

    private static let linkPatternRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"href=["']([^"']+)["']"#, options: [])
    }()

    // Лимиты безопасности для защиты от DoS через большие данные
    private static let maxTitleLength = 500
    private static let maxBodyLength = 5000

    /// Truncates string to prevent memory exhaustion attacks
    private static func truncate(_ string: String, maxLength: Int) -> String {
        if string.count <= maxLength {
            return string
        }
        return String(string.prefix(maxLength))
    }

    var domainModel: MegaplanNotification {
        MegaplanNotification(
            id: id,
            title: title,
            body: body,
            createdAt: createdAt,
            link: link,
            isRead: isRead,
            isMention: isMention,
            unreadCommentsCount: unreadCommentsCount,
            size: size,
            type: type,
            senderName: senderName,
            senderAvatarURL: senderAvatarURL,
            senderId: senderId
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        if let nestedKey = DynamicCodingKey(stringValue: "notification"),
           let nestedContainer = try? container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: nestedKey) {
            try self.init(container: nestedContainer)
        } else {
            try self.init(container: container)
        }
    }

    private init(container: KeyedDecodingContainer<DynamicCodingKey>) throws {
        self.id = try container.decodeFlexibleString(keys: ["id", "notificationId", "uuid"])

        // Парсим body из subject content (текст комментария) или основного content
        var parsedBody: String?

        if let subjectKey = DynamicCodingKey(stringValue: "subject"),
           let subjectContainer = try? container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: subjectKey) {
            if let subjectType = try? subjectContainer.decodeFlexibleString(keys: ["contentType"], defaultValue: nil),
               subjectType == "Comment" {
                if let rawContent = try? subjectContainer.decodeFlexibleString(keys: ["content"], defaultValue: nil) {
                    parsedBody = HTMLCleaner.fullClean(rawContent)
                }
            }
        }

        // Fallback на парсинг основного content
        if parsedBody == nil, let content = try? container.decodeFlexibleString(keys: ["content"], defaultValue: nil),
           !content.isEmpty {
            let contentParts = content.components(separatedBy: " :: ")
            if contentParts.count > 1 {
                parsedBody = HTMLCleaner.fullClean(contentParts[0])
            } else {
                parsedBody = HTMLCleaner.fullClean(content)
            }
        }

        // Парсим title из subject (имя задачи/сделки) или content
        var parsedTitle: String?
        var hasSubject = false

        if let subjectKey = DynamicCodingKey(stringValue: "subject"),
           let subjectContainer = try? container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: subjectKey) {
            hasSubject = true
            if let subjectType = try? subjectContainer.decodeFlexibleString(keys: ["contentType"], defaultValue: nil) {
                if subjectType == "Task" || subjectType == "Deal" {
                    if let rawName = try? subjectContainer.decodeFlexibleString(keys: ["name"], defaultValue: nil) {
                        parsedTitle = HTMLCleaner.extractTextFromLinks(rawName)
                    }
                }
            }
        }

        // Fallback на парсинг content
        if parsedTitle == nil, let content = try? container.decodeFlexibleString(keys: ["content"], defaultValue: nil),
           !content.isEmpty {
            let titleParts = content.components(separatedBy: " :: ")
            if titleParts.count > 1 {
                parsedTitle = HTMLCleaner.extractTextFromLinks(titleParts[1])
            }
        }

        // Определяем финальные title и body на основе типа уведомления
        let notificationType = try? container.decodeFlexibleString(keys: ["type"], defaultValue: nil)

        if let type = notificationType, type.hasPrefix("Bums") {
            AppLogger.debug("Bums event: \(type), parsedTitle: \(parsedTitle ?? "nil"), hasSubject: \(hasSubject)")
            if let title = parsedTitle, !title.isEmpty {
                self.title = Self.truncate(title, maxLength: Self.maxTitleLength)
                if let content = try? container.decodeFlexibleString(keys: ["content"], defaultValue: nil),
                   !content.isEmpty {
                    self.body = Self.truncate(HTMLCleaner.fullClean(content), maxLength: Self.maxBodyLength)
                } else {
                    self.body = ""
                }
            } else {
                if let content = try? container.decodeFlexibleString(keys: ["content"], defaultValue: nil),
                   !content.isEmpty {
                    self.title = ""
                    self.body = Self.truncate(HTMLCleaner.fullClean(content), maxLength: Self.maxBodyLength)
                } else {
                    self.title = String(localized: "notifications.untitled")
                    self.body = ""
                }
            }
        } else if !hasSubject && parsedBody?.isEmpty == false {
            self.title = Self.truncate(HTMLCleaner.fullClean(parsedBody ?? ""), maxLength: Self.maxTitleLength)
            self.body = ""
        } else {
            if parsedTitle?.isEmpty ?? true {
                let fallbackTitle = try container.decodeFlexibleString(keys: ["type", "title", "name", "header"], defaultValue: String(localized: "notifications.untitled"))
                parsedTitle = HTMLCleaner.fullClean(fallbackTitle)
            }
            self.title = Self.truncate(parsedTitle ?? String(localized: "notifications.untitled"), maxLength: Self.maxTitleLength)
            self.body = Self.truncate(parsedBody ?? "", maxLength: Self.maxBodyLength)
        }

        // Парсим link из content или subject
        var parsedLink: URL? = container.decodeFlexibleURL(keys: ["link", "url", "href"])

        if parsedLink == nil {
            if let subjectKey = DynamicCodingKey(stringValue: "subject"),
               let subjectContainer = try? container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: subjectKey) {
                parsedLink = subjectContainer.decodeFlexibleURL(keys: ["link", "url", "href"])
            }
        }

        // Извлекаем link из HTML content
        if parsedLink == nil, let content = try? container.decodeFlexibleString(keys: ["content"], defaultValue: nil) {
            if let regex = Self.linkPatternRegex,
               let match = regex.firstMatch(in: content, options: [], range: NSRange(location: 0, length: content.utf16.count)),
               let urlRange = Range(match.range(at: 1), in: content) {
                let urlString = String(content[urlRange])

                // Валидация схемы URL для защиты от XSS/phishing
                let allowedSchemes: Set<String> = ["http", "https"]

                if urlString.hasPrefix("/") {
                    if let url = URL(string: urlString) {
                        parsedLink = url
                    }
                } else if let url = URL(string: urlString),
                          let scheme = url.scheme?.lowercased(),
                          allowedSchemes.contains(scheme) {
                    parsedLink = url
                    AppLogger.debug("Validated and accepted URL with scheme: \(scheme)")
                } else if let url = URL(string: urlString) {
                    AppLogger.warning("Blocked URL with unsafe scheme: \(url.scheme ?? "none")")
                }
            }
        }

        self.link = parsedLink

        self.isRead = container.decodeFlexibleBool(keys: ["isRead", "read", "hasRead", "isUnread"], defaultValue: false)
        self.isMention = container.decodeFlexibleBool(keys: ["isMention"], defaultValue: false)

        // Парсим unreadCommentsCount из subject
        var parsedUnreadCount = 0
        if let subjectKey = DynamicCodingKey(stringValue: "subject"),
           let subjectContainer = try? container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: subjectKey) {
            if let subjectType = try? subjectContainer.decodeFlexibleString(keys: ["contentType"], defaultValue: nil),
               (subjectType == "Task" || subjectType == "Deal") {
                parsedUnreadCount = subjectContainer.decodeFlexibleInt(keys: ["unreadCommentsCount"], defaultValue: 0)
                AppLogger.debug("Parsed unreadCommentsCount: \(parsedUnreadCount) for subject type: \(subjectType)")
            }
        }

        let rootUnreadCount = container.decodeFlexibleInt(keys: ["unreadCommentsCount"], defaultValue: 0)
        if rootUnreadCount > 0 {
            parsedUnreadCount = rootUnreadCount
            AppLogger.debug("Parsed unreadCommentsCount from root: \(rootUnreadCount)")
        }

        self.unreadCommentsCount = parsedUnreadCount
        self.size = container.decodeFlexibleInt(keys: ["size"], defaultValue: 0)
        self.type = try? container.decodeFlexibleString(keys: ["type"], defaultValue: nil)

        // Парсим sender info через NotificationParser
        let senderInfo = NotificationParser.parseSenderInfo(from: container)
        var parsedSenderName = senderInfo.name
        let parsedAvatarURL = senderInfo.avatarURL
        let parsedSenderId = senderInfo.id

        // Fallback: извлекаем имя отправителя из content
        if parsedSenderName == nil,
           let content = try? container.decodeFlexibleString(keys: ["content"], defaultValue: nil),
           !content.isEmpty {
            parsedSenderName = NotificationParser.extractSenderNameFromContent(content)

            if parsedSenderName != nil {
                AppLogger.debug("Used content fallback for sender name")
            }
        }

        self.senderName = parsedSenderName
        self.senderAvatarURL = parsedAvatarURL
        self.senderId = parsedSenderId

        if parsedSenderName != nil || parsedAvatarURL != nil || parsedSenderId != nil {
            AppLogger.debug("Final sender info - Name: \(parsedSenderName ?? "nil"), ID: \(parsedSenderId ?? "nil"), Avatar: \(parsedAvatarURL?.absoluteString ?? "nil")")
        }

        // Парсим время из вложенной структуры
        if let timeKey = DynamicCodingKey(stringValue: "time"),
           let timeContainer = try? container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: timeKey),
           let timestamp = timeContainer.decodeFlexibleDate(keys: ["value"]) {
            self.createdAt = timestamp
        } else if let timestamp = container.decodeFlexibleDate(keys: ["createdAt", "created", "date", "time"]) {
            self.createdAt = timestamp
        } else {
            self.createdAt = Date()
        }
    }
}

// MARK: - Dynamic decoding helpers

struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

extension KeyedDecodingContainer where Key == DynamicCodingKey {
    func decodeFlexibleString(keys: [String], defaultValue: String? = nil) throws -> String {
        for name in keys {
            guard let key = DynamicCodingKey(stringValue: name) else { continue }

            if let value = try? decode(String.self, forKey: key) {
                return value
            }

            if let value = try? decode(Int.self, forKey: key) {
                return String(value)
            }

            if let value = try? decode(Double.self, forKey: key) {
                return String(value)
            }
        }

        if let defaultValue {
            return defaultValue
        }

        throw DecodingError.valueNotFound(
            String.self,
            DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Value not found for keys: \(keys.joined(separator: ", "))"
            )
        )
    }

    func decodeFlexibleInt(keys: [String], defaultValue: Int = 0) -> Int {
        for name in keys {
            guard let key = DynamicCodingKey(stringValue: name) else { continue }

            if let value = try? decode(Int.self, forKey: key) {
                return value
            }

            if let value = try? decode(String.self, forKey: key),
               let intValue = Int(value) {
                return intValue
            }
        }

        return defaultValue
    }

    func decodeFlexibleBool(keys: [String], defaultValue: Bool) -> Bool {
        for name in keys {
            guard let key = DynamicCodingKey(stringValue: name) else { continue }

            if let value = try? decode(Bool.self, forKey: key) {
                return value
            }

            if let intValue = try? decode(Int.self, forKey: key) {
                return intValue != 0
            }

            if let stringValue = try? decode(String.self, forKey: key) {
                return ["true", "1", "yes"].contains(stringValue.lowercased())
            }
        }

        return defaultValue
    }

    func decodeFlexibleURL(keys: [String]) -> URL? {
        for name in keys {
            guard let key = DynamicCodingKey(stringValue: name) else { continue }

            if let url = try? decode(URL.self, forKey: key) {
                return url
            }

            if let stringValue = try? decode(String.self, forKey: key),
               let url = URL(string: stringValue) {
                return url
            }
        }

        return nil
    }

    func decodeFlexibleDate(keys: [String]) -> Date? {
        for name in keys {
            guard let key = DynamicCodingKey(stringValue: name) else { continue }

            if let date = try? decode(Date.self, forKey: key) {
                return date
            }

            if let stringValue = try? decode(String.self, forKey: key),
               let parsed = DateParser.parse(stringValue) {
                return parsed
            }

            if let intValue = try? decode(Int.self, forKey: key) {
                // Валидация диапазона timestamp для защиты от overflow
                let minTimestamp = 0
                let maxTimestamp = 4102444800

                guard intValue >= minTimestamp && intValue <= maxTimestamp else {
                    AppLogger.warning("Timestamp out of valid range: \(intValue)")
                    continue
                }

                return Date(timeIntervalSince1970: TimeInterval(intValue))
            }
        }

        return nil
    }
}

enum DateParser {
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let shortISOFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let noTimezoneFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    private static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let standardFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    static func parse(_ value: String) -> Date? {
        if let date = isoFormatter.date(from: value) {
            return date
        }

        if let date = shortISOFormatter.date(from: value) {
            return date
        }

        if let date = noTimezoneFormatter.date(from: value) {
            return date
        }

        if let date = dateOnlyFormatter.date(from: value) {
            return date
        }

        if let date = standardFormatter.date(from: value) {
            return date
        }

        if let timeInterval = TimeInterval(value) {
            return Date(timeIntervalSince1970: timeInterval)
        }

        return nil
    }
}
