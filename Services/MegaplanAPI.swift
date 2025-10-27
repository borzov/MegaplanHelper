import Foundation

final class MegaplanAPI {
    private var baseURL: URL?
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.encoder = JSONEncoder()
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    func updateDomain(_ domain: String) {
        baseURL = Self.makeBaseURL(from: domain)
        AppLogger.debug("Updated domain to: \(domain), baseURL: \(baseURL?.absoluteString ?? "nil")")
    }

    func authenticate(login: String, password: String) async throws -> String {
        // Create multipart/form-data request
        let boundary = UUID().uuidString
        var body = Data()
        
        // Add username
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"username\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(login)\r\n".data(using: .utf8)!)
        
        // Add password
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"password\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(password)\r\n".data(using: .utf8)!)
        
        // Add grant_type
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"grant_type\"\r\n\r\n".data(using: .utf8)!)
        body.append("password\r\n".data(using: .utf8)!)
        
        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        let request = try makeRequest(
            path: "/api/v3/auth/access_token",
            method: "POST",
            body: body,
            token: nil,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )

        let response: AuthEnvelope = try await perform(request, decode: AuthEnvelope.self)
        guard let token = response.accessToken else {
            throw NetworkError.decodingFailed
        }
        return token
    }

    func validateToken(token: String) async throws -> (isValid: Bool, firstName: String?, unreadCount: Int?) {
        let request = try makeRequest(
            path: "/api/v3/currentUser",
            method: "GET",
            body: nil,
            token: token
        )

        do {
            let data = try await perform(request)
            
            // Parse user info
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = json["data"] as? [String: Any] {
                let firstName = dataDict["firstName"] as? String
                let unreadCount = dataDict["notificationsUnreadCount"] as? Int
                return (true, firstName, unreadCount)
            }
            
            return (true, nil, nil)
        } catch NetworkError.unauthorized {
            return (false, nil, nil)
        }
    }

    func fetchNotifications(token: String) async throws -> [MegaplanNotification] {
        let request = try makeRequest(
            path: "/api/v3/notification",
            method: "GET",
            body: nil,
            token: token
        )

        do {
            let data = try await perform(request)
            AppLogger.debug("Raw notifications response: \(String(data: data, encoding: .utf8) ?? "nil")")
            
            let envelope = try decoder.decode(NotificationsEnvelope.self, from: data)
            AppLogger.debug("Parsed \(envelope.items.count) notifications")
            return envelope.items.map { $0.domainModel }
        } catch {
            AppLogger.error("Failed to fetch notifications: \(error.localizedDescription)")
            throw NetworkError(error)
        }
    }

    func fetchUnreadCount(token: String) async throws -> Int {
        let request = try makeRequest(
            path: "/api/v3/notification/counter",
            method: "GET",
            body: nil,
            token: token
        )

        do {
            let envelope: CounterEnvelope = try await perform(request, decode: CounterEnvelope.self)
            return envelope.counter
        } catch {
            throw NetworkError(error)
        }
    }

    func markAsRead(id: String, token: String) async throws {
        let request = try makeRequest(
            path: "/api/v3/notification/\(id)",
            method: "DELETE",
            body: Data(),
            token: token,
            contentType: "application/json"
        )

        do {
            _ = try await perform(request)
        } catch {
            throw NetworkError(error)
        }
    }

    // MARK: - Internal request helpers

    private func makeRequest(path: String, method: String, body: Data?, token: String?, contentType: String? = nil) throws -> URLRequest {
        guard let baseURL else {
            throw NetworkError.invalidURL
        }

        // Ensure path starts with /
        let sanitizedPath = path.hasPrefix("/") ? path : "/\(path)"
        
        // Construct full URL properly
        let urlString = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let fullURLString = "\(urlString)\(sanitizedPath)"
        
        guard let url = URL(string: fullURLString) else {
            throw NetworkError.invalidURL
        }
        
        AppLogger.debug("Making request to: \(fullURLString)")
        AppLogger.debug("Base URL: \(baseURL.absoluteString)")
        
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.httpBody = body
            if let contentType = contentType {
                request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            } else if method != "DELETE" {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        } else if let contentType = contentType {
            // Set Content-Type even if body is nil (for DELETE requests with empty body)
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }

        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        // Log the request
        APILogger.logRequest(
            method: request.httpMethod ?? "UNKNOWN",
            url: request.url?.absoluteString ?? "UNKNOWN",
            headers: request.allHTTPHeaderFields,
            body: request.httpBody
        )
        
        let (data, response) = try await session.data(for: request)
        
        // Log the response
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        APILogger.logResponse(statusCode: statusCode, error: nil, data: data)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.server(message: String(localized: "error.invalidResponse"))
        }

        switch httpResponse.statusCode {
        case 200 ..< 300:
            return data
        case 401:
            throw NetworkError.unauthorized
        default:
            let serverMessage = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw NetworkError.server(message: serverMessage)
        }
    }

    private func perform<T: Decodable>(_ request: URLRequest, decode type: T.Type) async throws -> T {
        do {
            let data = try await perform(request)
            do {
                return try decoder.decode(type, from: data)
            } catch {
                AppLogger.error("Decoding error: \(error.localizedDescription)")
                throw NetworkError.decodingFailed
            }
        } catch {
            // Log the error
            APILogger.logResponse(statusCode: -1, error: error, data: nil)
            throw error
        }
    }

    private static func makeBaseURL(from domain: String) -> URL? {
        let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }

        return URL(string: "https://\(trimmed)")
    }
}

// MARK: - DTOs

private struct AuthEnvelope: Decodable {
    let accessToken: String?
    let expiresIn: Int?
    let tokenType: String?
    let scope: String?
    let refreshToken: String?
}

private struct NotificationsEnvelope: Decodable {
    let items: [NotificationDTO]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        
        // Try to decode data array directly
        if let dataKey = DynamicCodingKey(stringValue: "data") {
            if let dataArray = try? container.decode([NotificationDTO].self, forKey: dataKey) {
                self.items = dataArray
                return
            }
        }
        
        // Fallback to nested structure
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

private struct CounterEnvelope: Decodable {
    let counter: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        if let dataKey = DynamicCodingKey(stringValue: "data"),
           let dataContainer = try? container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: dataKey) {
            // Try both "count" and "counter" fields
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

private struct WrappedNotification: Decodable {
    let notification: NotificationDTO
}

private struct NotificationDTO: Decodable {
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
            type: type
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
        
        // Parse body from subject content (comment text) or main content
        var parsedBody: String?
        
        // Try to extract comment text from subject
        if let subjectKey = DynamicCodingKey(stringValue: "subject"),
           let subjectContainer = try? container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: subjectKey) {
            if let subjectType = try? subjectContainer.decodeFlexibleString(keys: ["contentType"], defaultValue: nil),
               subjectType == "Comment" {
                if let rawContent = try? subjectContainer.decodeFlexibleString(keys: ["content"], defaultValue: nil) {
                    parsedBody = HTMLCleaner.fullClean(rawContent)
                }
            }
        }
        
        // Fallback to main content parsing (extract comment part before ::)
        if parsedBody == nil, let content = try? container.decodeFlexibleString(keys: ["content"], defaultValue: nil),
           !content.isEmpty {
            let contentParts = content.components(separatedBy: " :: ")
            if contentParts.count > 1 {
                parsedBody = HTMLCleaner.fullClean(contentParts[0])
            } else {
                parsedBody = HTMLCleaner.fullClean(content)
            }
        }
        
        // Parse title from subject (task/deal name) or content
        var parsedTitle: String?
        var hasSubject = false
        
        // Try to extract from subject first
        if let subjectKey = DynamicCodingKey(stringValue: "subject"),
           let subjectContainer = try? container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: subjectKey) {
            hasSubject = true
            // Check if subject is a Task or Deal
            if let subjectType = try? subjectContainer.decodeFlexibleString(keys: ["contentType"], defaultValue: nil) {
                if subjectType == "Task" || subjectType == "Deal" {
                    if let rawName = try? subjectContainer.decodeFlexibleString(keys: ["name"], defaultValue: nil) {
                        parsedTitle = HTMLCleaner.extractTextFromLinks(rawName)
                    }
                }
            }
        }
        
        // Fallback to content parsing
        if parsedTitle == nil, let content = try? container.decodeFlexibleString(keys: ["content"], defaultValue: nil),
           !content.isEmpty {
            // Extract title from content (after :: separator)
            let titleParts = content.components(separatedBy: " :: ")
            if titleParts.count > 1 {
                parsedTitle = HTMLCleaner.extractTextFromLinks(titleParts[1])
            }
        }
        
        // Determine final title and body based on notification type
        let notificationType = try? container.decodeFlexibleString(keys: ["type"], defaultValue: nil)
        
        if let type = notificationType, type.hasPrefix("Bums") {
            // For Bums events, use parsed title (task/deal name) as title and content as body
            // If no parsed title, use content as body and clear title
            AppLogger.debug("Bums event: \(type), parsedTitle: \(parsedTitle ?? "nil"), hasSubject: \(hasSubject)")
            if let title = parsedTitle, !title.isEmpty {
                self.title = title
                if let content = try? container.decodeFlexibleString(keys: ["content"], defaultValue: nil),
                   !content.isEmpty {
                    self.body = HTMLCleaner.fullClean(content)
                } else {
                    self.body = ""
                }
            } else {
                // No title found, use content as body and clear title
                if let content = try? container.decodeFlexibleString(keys: ["content"], defaultValue: nil),
                   !content.isEmpty {
                    self.title = ""
                    self.body = HTMLCleaner.fullClean(content)
                } else {
                    self.title = String(localized: "notifications.untitled")
                    self.body = ""
                }
            }
        } else if !hasSubject && parsedBody?.isEmpty == false {
            // For service notifications without subject, use content as title and clear body
            self.title = HTMLCleaner.fullClean(parsedBody ?? "")
            self.body = ""
        } else {
            // Normal notifications with subject - apply fallback for title
            if parsedTitle == nil || parsedTitle!.isEmpty {
                let fallbackTitle = try container.decodeFlexibleString(keys: ["type", "title", "name", "header"], defaultValue: String(localized: "notifications.untitled"))
                parsedTitle = HTMLCleaner.fullClean(fallbackTitle)
            }
            self.title = parsedTitle ?? String(localized: "notifications.untitled")
            self.body = parsedBody ?? ""
        }
        
        // Parse link from content or subject
        var parsedLink: URL? = container.decodeFlexibleURL(keys: ["link", "url", "href"])
        
        if parsedLink == nil {
            // Try to extract from subject
            if let subjectKey = DynamicCodingKey(stringValue: "subject"),
               let subjectContainer = try? container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: subjectKey) {
                parsedLink = subjectContainer.decodeFlexibleURL(keys: ["link", "url", "href"])
            }
        }
        
        // Try to extract link from content HTML
        if parsedLink == nil, let content = try? container.decodeFlexibleString(keys: ["content"], defaultValue: nil) {
            // Extract URL from HTML links in content
            let pattern = #"href=["']([^"']+)["']"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: content, options: [], range: NSRange(location: 0, length: content.utf16.count)),
               let urlRange = Range(match.range(at: 1), in: content) {
                let urlString = String(content[urlRange])
                if urlString.hasPrefix("/") {
                    // Relative URL - construct full URL using baseURL
                    // Note: This requires baseURL to be accessible in static context
                    // For now, skip relative URL construction to avoid hardcoding domain
                    if let url = URL(string: urlString) {
                        parsedLink = url
                    }
                } else if let url = URL(string: urlString) {
                    parsedLink = url
                }
            }
        }
        
        self.link = parsedLink
        
        self.isRead = container.decodeFlexibleBool(keys: ["isRead", "read", "hasRead", "isUnread"], defaultValue: false)
        
        // Parse isMention flag
        self.isMention = container.decodeFlexibleBool(keys: ["isMention"], defaultValue: false)
        
        // Parse unreadCommentsCount from subject
        var parsedUnreadCount = 0
        if let subjectKey = DynamicCodingKey(stringValue: "subject"),
           let subjectContainer = try? container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: subjectKey) {
            if let subjectType = try? subjectContainer.decodeFlexibleString(keys: ["contentType"], defaultValue: nil),
               (subjectType == "Task" || subjectType == "Deal") {
                parsedUnreadCount = subjectContainer.decodeFlexibleInt(keys: ["unreadCommentsCount"], defaultValue: 0)
                AppLogger.debug("Parsed unreadCommentsCount: \(parsedUnreadCount) for subject type: \(subjectType)")
            }
        }
        
        // Also try to parse from root level
        let rootUnreadCount = container.decodeFlexibleInt(keys: ["unreadCommentsCount"], defaultValue: 0)
        if rootUnreadCount > 0 {
            parsedUnreadCount = rootUnreadCount
            AppLogger.debug("Parsed unreadCommentsCount from root: \(rootUnreadCount)")
        }
        
        self.unreadCommentsCount = parsedUnreadCount
        
        // Parse size
        self.size = try container.decodeFlexibleInt(keys: ["size"], defaultValue: 0)
        
        // Parse type
        self.type = try? container.decodeFlexibleString(keys: ["type"], defaultValue: nil)
        
        // Parse time from nested structure
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

private struct DynamicCodingKey: CodingKey {
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

private extension KeyedDecodingContainer where Key == DynamicCodingKey {
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
                return Date(timeIntervalSince1970: TimeInterval(intValue))
            }
        }

        return nil
    }
}

private enum DateParser {
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

        if let timeInterval = TimeInterval(value) {
            return Date(timeIntervalSince1970: timeInterval)
        }

        return standardFormatter.date(from: value)
    }
}

    