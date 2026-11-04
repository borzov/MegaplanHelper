import Foundation

/// Validated user information from token validation
struct ValidatedUser {
    let firstName: String
    let unreadCount: Int
    let possibleActions: [String]
}

final class MegaplanAPI: NSObject {
    private var baseURL: URL?
    /// True only after the lazy session has been materialized. deinit must not
    /// touch `pinnedLazySession` otherwise: the getter creates a URLSession that retains
    /// this delegate while the object is already deallocating (SIGSEGV).
    private var didCreateSession = false
    private let sessionOverride: URLSession?
    private var storedToken: String?
    private lazy var pinnedLazySession: URLSession = {
        didCreateSession = true
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = Constants.NetworkTimeouts.requestTimeout
        configuration.timeoutIntervalForResource = Constants.NetworkTimeouts.resourceTimeout
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private var activeSession: URLSession {
        sessionOverride ?? pinnedLazySession
    }

    init(domain: String = "", token: String? = nil, session: URLSession? = nil) {
        self.storedToken = token
        self.sessionOverride = session
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.encoder = JSONEncoder()
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
        super.init()
        if !domain.isEmpty {
            baseURL = Self.makeBaseURL(from: domain)
            AppLogger.debug("Updated domain to: \(domain), baseURL: \(baseURL?.absoluteString ?? "nil")")
        }
    }

    /// Новый экземпляр с тем же `sessionOverride`. Без подмены сессия снова ленивая, с pinning.
    func withCredentials(domain: String, token: String?) -> MegaplanAPI {
        MegaplanAPI(domain: domain, token: token, session: sessionOverride)
    }

    private func requiredToken() throws -> String {
        guard let storedToken, !storedToken.isEmpty else { throw NetworkError.missingToken }
        return storedToken
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

    func validateToken() async throws -> (isValid: Bool, firstName: String?, unreadCount: Int?, possibleActions: [String]?) {
        let token = try requiredToken()
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

    func fetchNotifications() async throws -> [MegaplanNotification] {
        do {
            let token = try requiredToken()
            let limit = 1000
            let queryDict: [String: Any] = ["limit": limit, "isActive": true]
            let queryData = try JSONSerialization.data(withJSONObject: queryDict)
            guard
                let queryJSON = String(data: queryData, encoding: .utf8),
                let encodedQuery = queryJSON.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            else {
                throw NetworkError.invalidURL
            }

            let request = try makeRequest(
                path: "/api/v3/notification?\(encodedQuery)",
                method: "GET",
                body: nil,
                token: token
            )

            let data = try await perform(request)
            let envelope = try decoder.decode(NotificationsEnvelope.self, from: data)
            let notifications = envelope.items.map(\.domainModel)
                .sorted { $0.createdAt > $1.createdAt }
            let seeds = ParticipantDirectory.seeds(fromNotificationJSON: data)
                + ParticipantDirectory.seeds(fromParsed: notifications)
            await UserInfoResolver.shared.remember(seeds: seeds)

            AppLogger.debug("Parsed \(notifications.count) active notifications (single request, limit=\(limit))")
            return notifications
        } catch {
            AppLogger.error("Failed to fetch notifications: \(error.localizedDescription)")
            throw NetworkError(error)
        }
    }

    func fetchUnreadCount() async throws -> Int {
        let request = try makeRequest(
            path: "/api/v3/notification/counter",
            method: "GET",
            body: nil,
            token: try requiredToken()
        )

        do {
            let envelope: CounterEnvelope = try await perform(request, decode: CounterEnvelope.self)
            return envelope.counter
        } catch {
            throw NetworkError(error)
        }
    }

    func markAsRead(id: String) async throws {
        let request = try makeRequest(
            path: "/api/v3/notification/\(id)",
            method: "DELETE",
            body: Data(),
            token: try requiredToken(),
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
            let (data, response) = try await activeSession.data(for: request)
            
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
                throw NetworkError.timedOut
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
        guard didCreateSession else { return }
        pinnedLazySession.invalidateAndCancel()
    }
}

// MARK: - Task endpoints

extension MegaplanAPI {
    func fetchTasks(currentUserId: String,
                    sortBy: TaskSortKey,
                    statusFilter: TaskStatusFilter,
                    limit: Int = 100) async throws -> [MegaplanTask] {
        let token = try requiredToken()
        guard !currentUserId.isEmpty else {
            throw NetworkError.missingToken
        }

        // Megaplan v3 expects the WHOLE query string to be a single JSON object,
        // not URL-encoded `?key=value` pairs. Server explicitly enforces this:
        //   "Query string should be json. For example /api/v3/uri?{\"key\": \"value\"}"
        let filterTree = MegaplanTaskFilterBuilder.buildMyTasksFilter(currentUserId: currentUserId)
        let sortField: [String: Any] = [
            "contentType": "SortField",
            "fieldName": sortBy.apiFieldName,
            "desc": true
        ]

        var queryDict: [String: Any] = [
            "filter": filterTree,
            "sortBy": [sortField],
            "limit": limit,
            "fields": [
                "responsible",
                "owner",
                "auditors",
                "executors",
                "activity",
                "timeCreated",
                "lastCommentTimeCreated",
                "unreadCommentsCount",
                "commentsCount",
                "humanNumber",
                "status",
                "name"
            ]
        ]
        if let statuses = statusFilter.apiStatuses {
            queryDict["statuses"] = statuses
        }

        let path: String
        do {
            path = try Self.buildJSONQueryPath("/api/v3/task", query: queryDict)
        } catch {
            AppLogger.error("Failed to build task query JSON: \(error.localizedDescription)")
            throw NetworkError.decodingFailed
        }

        let request = try makeRequest(path: path, method: "GET", body: nil, token: token)

        do {
            let data = try await perform(request)
            AppLogger.debug("Raw tasks response (\(data.count) bytes)")
            do {
                let envelope = try decoder.decode(TaskListEnvelope.self, from: data)
                AppLogger.debug("Parsed \(envelope.items.count) tasks")

                // Имя и аватар из ответа кладём в справочник, не в ящик напрямую.
                await UserInfoResolver.shared.remember(seeds: ParticipantDirectory.seeds(fromTaskJSON: data))

                // Megaplan v3 returns `responsible` / `owner` as a `{id, contentType}`
                // ContentLink for most tasks (only a handful expose the full Employee
                // object inline). Backfill missing names by hitting `/api/v3/employee/{id}`
                // in parallel before publishing — keeps the UI free of placeholder
                // "Создатель неизвестен" rows that never get resolved by the lazy task-row
                // path.
                let enriched = await self.enrichParticipants(in: envelope.items)

                return enriched
            } catch {
                AppLogger.error("Failed to decode tasks: \(error.localizedDescription)")
                throw NetworkError.decodingFailed
            }
        } catch {
            throw NetworkError(error)
        }
    }

    /// Resolves the names + avatars of every `responsible` / `owner` participant
    /// whose `name` is missing in the list response. Hits each unique employee id
    /// at most once via `withTaskGroup`, then remembers the seeds so the
    /// in-row resolver has cache hits later.
    private func enrichParticipants(in tasks: [MegaplanTask]) async -> [MegaplanTask] {
        var idsNeeded = Set<String>()
        for task in tasks {
            if let p = task.responsible, !p.id.isEmpty, p.name.isEmpty { idsNeeded.insert(p.id) }
            if let p = task.owner, !p.id.isEmpty, p.name.isEmpty { idsNeeded.insert(p.id) }
        }
        guard !idsNeeded.isEmpty else { return tasks }

        let resolved: [String: (name: String?, avatarURL: URL?)] = await withTaskGroup(
            of: (String, String?, URL?).self
        ) { group in
            for id in idsNeeded {
                group.addTask { [self] in
                    do {
                        let result = try await self.fetchEmployee(id: id)
                        return (id, result.name, result.avatarURL)
                    } catch {
                        AppLogger.warning("enrichParticipants fetchEmployee(\(id)) failed: \(error.localizedDescription)")
                        return (id, nil, nil)
                    }
                }
            }
            var out: [String: (String?, URL?)] = [:]
            for await (id, name, avatar) in group where (name != nil) || (avatar != nil) {
                out[id] = (name, avatar)
            }
            return out
        }

        let seeds = resolved.map { id, value in
            ParticipantSeed(id: id, name: value.name, avatarURL: value.avatarURL)
        }
        await UserInfoResolver.shared.remember(seeds: seeds)
        AppLogger.debug("enrichParticipants resolved \(resolved.count)/\(idsNeeded.count) employees")

        func merge(_ p: TaskParticipant?) -> TaskParticipant? {
            guard let p else { return nil }
            if !p.name.isEmpty { return p }
            guard let extra = resolved[p.id] else { return p }
            return TaskParticipant(
                id: p.id,
                contentType: p.contentType,
                name: extra.name ?? p.name,
                avatarURL: extra.avatarURL ?? p.avatarURL
            )
        }

        return tasks.map { task in
            MegaplanTask(
                id: task.id,
                name: task.name,
                status: task.status,
                responsible: merge(task.responsible),
                owner: merge(task.owner),
                auditors: task.auditors,
                executors: task.executors,
                timeCreated: task.timeCreated,
                activity: task.activity,
                lastCommentTimeCreated: task.lastCommentTimeCreated,
                totalCommentsCount: task.totalCommentsCount,
                unreadCommentsCount: task.unreadCommentsCount,
                humanNumber: task.humanNumber
            )
        }
    }

    func searchTasks(currentUserId: String,
                     query: String,
                     limit: Int = 30) async throws -> [MegaplanTask] {
        let token = try requiredToken()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !currentUserId.isEmpty else {
            throw NetworkError.missingToken
        }

        let filterTree = MegaplanTaskFilterBuilder.buildMyTasksFilter(currentUserId: currentUserId)
        var queryDict: [String: Any] = [
            "filter": filterTree,
            "limit": limit,
            "fields": [
                "responsible",
                "owner",
                "auditors",
                "executors",
                "activity",
                "timeCreated",
                "lastCommentTimeCreated",
                "unreadCommentsCount",
                "commentsCount",
                "humanNumber",
                "status",
                "name"
            ],
            "q": trimmed
        ]
        // No sortBy on search — let the server return relevance-ranked matches.
        _ = queryDict.removeValue(forKey: "sortBy")

        let path: String
        do {
            path = try Self.buildJSONQueryPath("/api/v3/task", query: queryDict)
        } catch {
            AppLogger.error("Failed to build task search query JSON: \(error.localizedDescription)")
            throw NetworkError.decodingFailed
        }

        let request = try makeRequest(path: path, method: "GET", body: nil, token: token)
        do {
            let data = try await perform(request)
            do {
                let envelope = try decoder.decode(TaskListEnvelope.self, from: data)
                await UserInfoResolver.shared.remember(seeds: ParticipantDirectory.seeds(fromTaskJSON: data))
                AppLogger.debug("Server search '\(trimmed)' returned \(envelope.items.count) tasks")
                let enriched = await self.enrichParticipants(in: envelope.items)
                return enriched
            } catch {
                AppLogger.error("Failed to decode search response: \(error.localizedDescription)")
                throw NetworkError.decodingFailed
            }
        } catch {
            throw NetworkError(error)
        }
    }

    func fetchTaskComments(taskId: String) async throws -> TaskCommentsBundle {
        let token = try requiredToken()
        guard !taskId.isEmpty else { throw NetworkError.missingToken }

        // Step 1 — fetch the task with the inline comments array. We ask for
        // the fields we know come back populated; the per-comment fan-out below
        // backfills `owner` / `timeCreated` / `attaches` which the inline form
        // omits.
        let taskQuery: [String: Any] = [
            "fields": ["id", "name", "humanNumber", "comments"]
        ]
        let taskPath: String
        do {
            taskPath = try Self.buildJSONQueryPath("/api/v3/task/\(taskId)", query: taskQuery)
        } catch {
            throw NetworkError.decodingFailed
        }
        let taskRequest = try makeRequest(path: taskPath, method: "GET", body: nil, token: token)
        let taskData: Data
        do {
            taskData = try await perform(taskRequest)
        } catch {
            throw NetworkError(error)
        }

        guard let json = try? JSONSerialization.jsonObject(with: taskData) as? [String: Any],
              let dataDict = json["data"] as? [String: Any] else {
            throw NetworkError.decodingFailed
        }
        let taskName = (dataDict["name"] as? String) ?? ""
        let humanNumber = Self.intValue(dataDict["humanNumber"])
        let commentArray = (dataDict["comments"] as? [[String: Any]]) ?? []
        let commentIds = commentArray.compactMap { $0["id"] as? String }

        // Step 2 — fan out one /comment/{id} request per id so we get owner,
        // timeCreated, attachments, etc. Megaplan inline `comments` returns
        // only id + isUnread + (sometimes) content.
        let comments = await withTaskGroup(of: (Int, MegaplanComment?).self) { group -> [MegaplanComment] in
            for (idx, commentId) in commentIds.enumerated() {
                group.addTask { [self] in
                    do {
                        let comment = try await self.fetchSingleComment(id: commentId)
                        return (idx, comment)
                    } catch {
                        AppLogger.warning("fetchSingleComment(\(commentId)) failed: \(error.localizedDescription)")
                        return (idx, nil)
                    }
                }
            }
            var ordered = Array<MegaplanComment?>(repeating: nil, count: commentIds.count)
            for await (idx, comment) in group {
                ordered[idx] = comment
            }
            return ordered.compactMap { $0 }
        }

        // Stable sort: oldest first if we have timestamps, otherwise keep server order.
        let sorted = comments.sorted { lhs, rhs in
            switch (lhs.timeCreated, rhs.timeCreated) {
            case let (l?, r?): return l < r
            case (nil, _?): return true
            case (_?, nil): return false
            default: return false
            }
        }
        return TaskCommentsBundle(taskName: taskName, humanNumber: humanNumber, comments: sorted)
    }

    private func fetchSingleComment(id: String) async throws -> MegaplanComment {
        let path = try Self.buildJSONQueryPath("/api/v3/comment/\(id)", query: ["fields": [
            "id", "content", "owner", "timeCreated", "attaches", "forwardFrom"
        ]])
        let request = try makeRequest(path: path, method: "GET", body: nil, token: try requiredToken())
        let data = try await perform(request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dict = json["data"] as? [String: Any] else {
            throw NetworkError.decodingFailed
        }
        return Self.parseComment(dict)
    }

    private static func parseComment(_ dict: [String: Any]) -> MegaplanComment {
        let id = (dict["id"] as? String) ?? UUID().uuidString
        let content = (dict["content"] as? String) ?? ""
        let timeCreated = parseDateTime(dict["timeCreated"])

        let ownerDict = dict["owner"] as? [String: Any]
        let authorName = ownerDict.flatMap { NotificationParser.extractName(from: $0) }
        let authorId = ownerDict?["id"] as? String

        let attachments = ((dict["attaches"] as? [[String: Any]]) ?? []).map { entry -> MegaplanComment.Attachment in
            let name = (entry["name"] as? String) ?? "—"
            let url = parseAttachmentURL(entry)
            return .init(name: name, url: url)
        }

        let forwarded: MegaplanComment.ForwardedComment? = (dict["forwardFrom"] as? [String: Any]).map { fwd in
            let fwdContent = (fwd["content"] as? String) ?? ""
            let fwdTime = parseDateTime(fwd["timeCreated"])
            let fwdOwner = fwd["owner"] as? [String: Any]
            let fwdAuthor = fwdOwner.flatMap { NotificationParser.extractName(from: $0) }
            return .init(authorName: fwdAuthor, timeCreated: fwdTime, contentHTML: fwdContent)
        }

        return MegaplanComment(id: id,
                               authorName: authorName,
                               authorId: authorId,
                               timeCreated: timeCreated,
                               contentHTML: content,
                               attachments: attachments,
                               forwardedFrom: forwarded)
    }

    private static func parseDateTime(_ raw: Any?) -> Date? {
        guard let dict = raw as? [String: Any], let iso = dict["value"] as? String else {
            return nil
        }
        return DateParser.parse(iso)
    }

    private static func parseAttachmentURL(_ entry: [String: Any]) -> URL? {
        if let path = entry["path"] as? String, !path.isEmpty {
            // Path is server-relative; the markdown export keeps it as-is so
            // the receiver can reconstruct the full URL via the configured host.
            if path.hasPrefix("http://") || path.hasPrefix("https://") {
                return URL(string: path)
            }
            // Leave relative paths un-prefixed; URL(string:) returns nil for
            // server-relative paths without a base, which the exporter handles.
            return URL(string: path)
        }
        return nil
    }

    private static func intValue(_ raw: Any?) -> Int? {
        if let i = raw as? Int { return i }
        if let s = raw as? String, let i = Int(s) { return i }
        if let d = raw as? Double { return Int(d) }
        return nil
    }

    func fetchEmployee(id: String) async throws -> (name: String?, avatarURL: URL?) {
        let request = try makeRequest(path: "/api/v3/employee/\(id)", method: "GET", body: nil, token: try requiredToken())
        let data = try await perform(request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any] else {
            throw NetworkError.decodingFailed
        }
        let name = NotificationParser.extractName(from: dataDict)
        let avatarURL = NotificationParser.extractAvatarURL(from: dataDict)
        return (name, avatarURL)
    }

    func fetchCurrentUserId() async throws -> String {
        let request = try makeRequest(path: "/api/v3/currentUser", method: "GET", body: nil, token: try requiredToken())
        do {
            let data = try await perform(request)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataDict = json["data"] as? [String: Any] else {
                AppLogger.error("currentUser response missing 'data' object")
                throw NetworkError.decodingFailed
            }

            if let id = dataDict["id"] as? String, !id.isEmpty {
                return id
            }
            if let intId = dataDict["id"] as? Int {
                return String(intId)
            }

            AppLogger.error("currentUser response missing 'id' field")
            throw NetworkError.decodingFailed
        } catch {
            throw NetworkError(error)
        }
    }

    /// Builds a `/path?<percent-encoded JSON>` string, the format Megaplan v3 expects.
    private static func buildJSONQueryPath(_ basePath: String, query: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: query, options: [.sortedKeys])
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw NetworkError.decodingFailed
        }
        // Encode characters that aren't valid in URL queries — primarily { } [ ] " < > and backslash.
        // RFC 3986 sub-delims (: , ; etc.) stay unescaped, which JSON parses cleanly.
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=#?")  // also escape these to avoid query-key confusion
        guard let encoded = jsonString.addingPercentEncoding(withAllowedCharacters: allowed) else {
            throw NetworkError.decodingFailed
        }
        return "\(basePath)?\(encoded)"
    }
}