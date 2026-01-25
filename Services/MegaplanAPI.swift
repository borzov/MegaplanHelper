import Foundation

/// Validated user information from token validation
struct ValidatedUser {
    let firstName: String
    let unreadCount: Int
    let possibleActions: [String]
}

protocol AuthenticationService {
    func authenticate(login: String, password: String) async throws -> String
    func validateToken(token: String) async throws -> (isValid: Bool, firstName: String?, unreadCount: Int?, possibleActions: [String]?)
}

protocol NotificationService {
    func fetchNotifications(token: String) async throws -> [MegaplanNotification]
    func fetchUnreadCount(token: String) async throws -> Int
    func markAsRead(id: String, token: String) async throws
}

final class MegaplanAPI: NSObject, AuthenticationService, NotificationService {
    private var baseURL: URL?
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = Constants.NetworkTimeouts.requestTimeout
        configuration.timeoutIntervalForResource = Constants.NetworkTimeouts.resourceTimeout
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    override init() {
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.encoder = JSONEncoder()
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
        super.init()
    }

    func updateDomain(_ domain: String) {
        baseURL = Self.makeBaseURL(from: domain)
        AppLogger.debug("Updated domain to: \(domain), baseURL: \(baseURL?.absoluteString ?? "nil")")
    }

    func authenticate(login: String, password: String) async throws -> String {
        // Create multipart/form-data request
        let boundary = UUID().uuidString
        var body = Data()

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"username\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(login)\r\n".data(using: .utf8)!)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"password\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(password)\r\n".data(using: .utf8)!)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"grant_type\"\r\n\r\n".data(using: .utf8)!)
        body.append("password\r\n".data(using: .utf8)!)

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

    func validateToken(token: String) async throws -> (isValid: Bool, firstName: String?, unreadCount: Int?, possibleActions: [String]?) {
        let request = try makeRequest(
            path: "/api/v3/currentUser",
            method: "GET",
            body: nil,
            token: token
        )

        do {
            let data = try await perform(request)

            // Parse user info with strict validation
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                AppLogger.error("Token validation: Failed to parse JSON response")
                throw NetworkError.decodingFailed
            }

            guard let dataDict = json["data"] as? [String: Any] else {
                AppLogger.error("Token validation: Missing 'data' field in response")
                throw NetworkError.decodingFailed
            }

            // firstName is optional but should be present for valid users
            let firstName = dataDict["firstName"] as? String
            if firstName == nil {
                AppLogger.warning("Token validation: firstName field is missing")
            }

            // unreadCount defaults to 0 if missing
            let unreadCount = dataDict["notificationsUnreadCount"] as? Int ?? 0

            // Extract possibleActions array
            var possibleActions: [String] = []
            if let actions = dataDict["possibleActions"] as? [String] {
                possibleActions = actions
            } else if let actions = dataDict["possibleActions"] as? [Any] {
                // Handle case where actions might be objects or other types
                possibleActions = actions.compactMap { $0 as? String }
                if possibleActions.count != actions.count {
                    AppLogger.warning("Token validation: Some possibleActions could not be converted to String")
                }
            } else {
                AppLogger.debug("Token validation: possibleActions field is missing or invalid")
            }

            AppLogger.debug("Token validation succeeded: firstName=\(firstName ?? "nil"), unreadCount=\(unreadCount), permissions=\(possibleActions.count)")
            return (true, firstName, unreadCount, possibleActions.isEmpty ? nil : possibleActions)
        } catch NetworkError.unauthorized {
            AppLogger.info("Token validation: Unauthorized (token expired or invalid)")
            return (false, nil, nil, nil)
        } catch {
            AppLogger.error("Token validation failed with error: \(error.localizedDescription)")
            throw error
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
            
            let notifications = envelope.items.map { $0.domainModel }
            
            // Extract and cache user info from notifications
            let userInfoMap = extractUserInfoFromNotifications(data: data)
            await cacheUserInfoFromNotifications(userInfoMap: userInfoMap, notifications: notifications)
            
            return notifications
        } catch {
            AppLogger.error("Failed to fetch notifications: \(error.localizedDescription)")
            throw NetworkError(error)
        }
    }
    
    // MARK: - User Info Extraction and Caching
    
    private func extractUserInfoFromNotifications(data: Data) -> [String: (name: String?, avatarURL: URL?)] {
        var userInfoMap: [String: (name: String?, avatarURL: URL?)] = [:]
        
        // Extract user info from all notifications (including from subject fields)
        // We need to parse the raw JSON to extract user info from nested fields
        guard let jsonData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = jsonData["data"] as? [[String: Any]] else {
            return userInfoMap
        }
        
        for notificationDict in dataArray {
            // Extract from sender
            if let sender = notificationDict["sender"] as? [String: Any],
               let senderId = sender["id"] as? String {
                extractAndStoreUserInfo(from: sender, userId: senderId, into: &userInfoMap, source: "sender")
            }
            
            // Extract from subject (can be Task, Deal, or Comment)
            if let subject = notificationDict["subject"] as? [String: Any] {
                extractUserInfoFromSubject(subject, into: &userInfoMap)
            }
        }
        
        return userInfoMap
    }
    
    private func extractAndStoreUserInfo(from dict: [String: Any], userId: String, into userInfoMap: inout [String: (name: String?, avatarURL: URL?)], source: String) {
        let name = NotificationParser.extractName(from: dict)
        let avatarURL = NotificationParser.extractAvatarURL(from: dict)
        
        if let name = name, let avatarURL = avatarURL {
            if userInfoMap[userId] == nil || userInfoMap[userId]?.avatarURL == nil {
                userInfoMap[userId] = (name, avatarURL)
                AppLogger.debug("Extracted user info from \(source) for \(userId) - Name: \(name), Avatar: \(avatarURL.absoluteString)")
            }
        }
    }
    
    /// Extract Task owner and responsible user info
    private func extractTaskUserInfo(from task: [String: Any], into userInfoMap: inout [String: (name: String?, avatarURL: URL?)], sourcePrefix: String) {
        if let owner = task["owner"] as? [String: Any],
           let ownerId = owner["id"] as? String {
            extractAndStoreUserInfo(from: owner, userId: ownerId, into: &userInfoMap, source: "\(sourcePrefix).owner")
        }

        if let responsible = task["responsible"] as? [String: Any],
           let responsibleId = responsible["id"] as? String {
            extractAndStoreUserInfo(from: responsible, userId: responsibleId, into: &userInfoMap, source: "\(sourcePrefix).responsible")
        }
    }

    /// Extract Deal manager user info
    private func extractDealUserInfo(from deal: [String: Any], into userInfoMap: inout [String: (name: String?, avatarURL: URL?)], sourcePrefix: String) {
        if let manager = deal["manager"] as? [String: Any],
           let managerId = manager["id"] as? String {
            extractAndStoreUserInfo(from: manager, userId: managerId, into: &userInfoMap, source: "\(sourcePrefix).manager")
        }
    }

    private func extractUserInfoFromSubject(_ subject: [String: Any], into userInfoMap: inout [String: (name: String?, avatarURL: URL?)]) {
        let subjectType = subject["contentType"] as? String

        // Handle Task directly
        if subjectType == "Task" {
            extractTaskUserInfo(from: subject, into: &userInfoMap, sourcePrefix: "subject.task")
        }

        // Handle Deal directly
        if subjectType == "Deal" {
            extractDealUserInfo(from: subject, into: &userInfoMap, sourcePrefix: "subject.deal")
        }

        // Handle Comment -> Task/Deal (nested structure)
        if subjectType == "Comment",
           let nestedSubject = subject["subject"] as? [String: Any] {
            let nestedSubjectType = nestedSubject["contentType"] as? String

            // Comment -> Task -> owner/responsible
            if nestedSubjectType == "Task" {
                extractTaskUserInfo(from: nestedSubject, into: &userInfoMap, sourcePrefix: "subject.comment.task")
            }

            // Comment -> Deal -> manager
            if nestedSubjectType == "Deal" {
                extractDealUserInfo(from: nestedSubject, into: &userInfoMap, sourcePrefix: "subject.comment.deal")
            }
        }
    }
    
    private func cacheUserInfoFromNotifications(userInfoMap: [String: (name: String?, avatarURL: URL?)], notifications: [MegaplanNotification]) async {
        // Cache all collected user info from JSON parsing
        for (userId, info) in userInfoMap {
            if let name = info.name, let avatarURL = info.avatarURL {
                await UserInfoCache.shared.cacheUserInfo(
                    userId: userId,
                    name: name,
                    avatarURL: avatarURL
                )
                AppLogger.debug("Cached user info for \(userId) from notification parsing (with avatar) - Name: \(name), Avatar: \(avatarURL.absoluteString)")
            }
        }
        
        // Also cache from parsed notifications (for backward compatibility)
        for notification in notifications {
            if let senderId = notification.senderId {
                if let senderName = notification.senderName,
                   let senderAvatarURL = notification.senderAvatarURL {
                    // Only cache if not already cached
                    if await UserInfoCache.shared.getUserInfo(for: senderId) == nil {
                        await UserInfoCache.shared.cacheUserInfo(
                            userId: senderId,
                            name: senderName,
                            avatarURL: senderAvatarURL
                        )
                        AppLogger.debug("Cached user info for \(senderId) from notification parsing (with avatar) - Name: \(senderName), Avatar: \(senderAvatarURL.absoluteString)")
                    }
                } else {
                    AppLogger.debug("Skipping cache for \(senderId) - missing data: name=\(notification.senderName ?? "nil"), avatar=\(notification.senderAvatarURL?.absoluteString ?? "nil")")
                }
            }
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
        
        do {
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
        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                throw NetworkError.offline
            case .timedOut:
                throw NetworkError.transport(message: String(localized: "error.timeout"))
            default:
                throw NetworkError.transport(message: urlError.localizedDescription)
            }
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
        return URLValidator.validateDomain(domain)
    }

    deinit {
        session.invalidateAndCancel()
    }
}