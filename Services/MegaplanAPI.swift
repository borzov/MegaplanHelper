import CommonCrypto
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
    
    private func extractUserInfoFromSubject(_ subject: [String: Any], into userInfoMap: inout [String: (name: String?, avatarURL: URL?)]) {
        let subjectType = subject["contentType"] as? String
        
        // Handle Task directly
        if subjectType == "Task" {
            if let owner = subject["owner"] as? [String: Any],
               let ownerId = owner["id"] as? String {
                extractAndStoreUserInfo(from: owner, userId: ownerId, into: &userInfoMap, source: "subject.task.owner")
            }
            
            if let responsible = subject["responsible"] as? [String: Any],
               let responsibleId = responsible["id"] as? String {
                extractAndStoreUserInfo(from: responsible, userId: responsibleId, into: &userInfoMap, source: "subject.task.responsible")
            }
        }
        
        // Handle Deal directly
        if subjectType == "Deal",
           let manager = subject["manager"] as? [String: Any],
           let managerId = manager["id"] as? String {
            extractAndStoreUserInfo(from: manager, userId: managerId, into: &userInfoMap, source: "subject.deal.manager")
        }
        
        // Handle Comment -> Task/Deal (nested structure)
        if subjectType == "Comment",
           let nestedSubject = subject["subject"] as? [String: Any] {
            let nestedSubjectType = nestedSubject["contentType"] as? String
            
            // Comment -> Task -> owner/responsible
            if nestedSubjectType == "Task" {
                if let owner = nestedSubject["owner"] as? [String: Any],
                   let ownerId = owner["id"] as? String {
                    extractAndStoreUserInfo(from: owner, userId: ownerId, into: &userInfoMap, source: "subject.comment.task.owner")
                }
                
                if let responsible = nestedSubject["responsible"] as? [String: Any],
                   let responsibleId = responsible["id"] as? String {
                    extractAndStoreUserInfo(from: responsible, userId: responsibleId, into: &userInfoMap, source: "subject.comment.task.responsible")
                }
            }
            
            // Comment -> Deal -> manager
            if nestedSubjectType == "Deal",
               let manager = nestedSubject["manager"] as? [String: Any],
               let managerId = manager["id"] as? String {
                extractAndStoreUserInfo(from: manager, userId: managerId, into: &userInfoMap, source: "subject.comment.deal.manager")
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
        let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        // Construct URL string with scheme if not present
        let urlString: String
        if trimmed.hasPrefix("https://") || trimmed.hasPrefix("http://") {
            urlString = trimmed
        } else {
            urlString = "https://\(trimmed)"
        }

        // Use URLComponents for proper parsing
        guard var components = URLComponents(string: urlString) else {
            AppLogger.warning("Invalid URL format: \(domain)")
            return nil
        }

        // Ensure HTTPS scheme
        if components.scheme == "http" {
            components.scheme = "https"
        }

        // Validate scheme is HTTPS only
        guard components.scheme == "https" else {
            AppLogger.warning("Blocked non-HTTPS scheme: \(domain)")
            return nil
        }

        // Extract and validate host
        guard let host = components.host, !host.isEmpty else {
            AppLogger.warning("No host in URL: \(domain)")
            return nil
        }

        // Block URLs with query parameters or fragments (potential injection)
        if components.query != nil || components.fragment != nil {
            AppLogger.warning("Blocked URL with query/fragment: \(domain)")
            return nil
        }

        // Block URLs with user info (username:password@host)
        if components.user != nil || components.password != nil {
            AppLogger.warning("Blocked URL with credentials: \(domain)")
            return nil
        }

        // SSRF protection: validate host against blocklist
        if isBlockedHost(host) {
            AppLogger.warning("Blocked potentially unsafe domain: \(domain)")
            return nil
        }

        // Construct clean URL with only scheme and host (and optional port)
        var cleanComponents = URLComponents()
        cleanComponents.scheme = "https"
        cleanComponents.host = host
        cleanComponents.port = components.port

        return cleanComponents.url
    }

    /// Checks if host matches any blocked pattern for SSRF protection
    private static func isBlockedHost(_ host: String) -> Bool {
        let lowercasedHost = host.lowercased()

        // Block localhost variants
        if lowercasedHost == "localhost" ||
           lowercasedHost.hasSuffix(".localhost") ||
           lowercasedHost == "localhost.localdomain" {
            return true
        }

        // Block IP address patterns
        let blockedIPPrefixes = [
            "127.", "0.0.0.0", "0.",  // Loopback and zero addresses
            "10.",                     // Class A private
            "172.16.", "172.17.", "172.18.", "172.19.",
            "172.20.", "172.21.", "172.22.", "172.23.",
            "172.24.", "172.25.", "172.26.", "172.27.",
            "172.28.", "172.29.", "172.30.", "172.31.",  // Class B private
            "192.168.",                // Class C private
            "169.254.",                // Link-local
            "224.", "225.", "226.", "227.", "228.", "229.",
            "230.", "231.", "232.", "233.", "234.", "235.",
            "236.", "237.", "238.", "239.",  // Multicast
            "255."                     // Broadcast
        ]

        for prefix in blockedIPPrefixes {
            if lowercasedHost.hasPrefix(prefix) {
                return true
            }
        }

        // Block IPv6 localhost and private addresses
        let blockedIPv6Patterns = [
            "::1", "[::1]",           // IPv6 loopback
            "fe80:", "[fe80:",        // Link-local
            "fc00:", "[fc00:",        // Unique local
            "fd00:", "[fd00:"         // Unique local
        ]

        for pattern in blockedIPv6Patterns {
            if lowercasedHost.hasPrefix(pattern) || lowercasedHost.contains(pattern) {
                return true
            }
        }

        // Block metadata service endpoints (cloud environments)
        let metadataHosts = [
            "169.254.169.254",        // AWS/GCP/Azure metadata
            "metadata.google.internal",
            "metadata.goog"
        ]

        if metadataHosts.contains(lowercasedHost) {
            return true
        }

        return false
    }

    deinit {
        session.invalidateAndCancel()
    }
}

// MARK: - Certificate Pinning State

extension Notification.Name {
    /// Posted when certificate pinning fails but connection is allowed (graceful degradation)
    static let certificatePinningFailed = Notification.Name("MegaplanCertificatePinningFailed")
}

/// Thread-safe wrapper for certificate pinning failure state
private final class PinningState {
    private var _pinningFailureNotified = false
    private let lock = NSLock()

    var pinningFailureNotified: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _pinningFailureNotified
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _pinningFailureNotified = newValue
        }
    }

    func setNotifiedIfNeeded() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if _pinningFailureNotified {
            return false
        }
        _pinningFailureNotified = true
        return true
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        _pinningFailureNotified = false
    }
}

// MARK: - URLSessionDelegate (Certificate Pinning)

extension MegaplanAPI: URLSessionDelegate {
    /// Thread-safe state for tracking pinning failures
    private static let pinningState = PinningState()

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Skip pinning in debug builds to allow proxy debugging
        guard Constants.CertificatePinning.isEnabled else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Validate certificate chain (standard TLS validation)
        let policies = [SecPolicyCreateSSL(true, challenge.protectionSpace.host as CFString)]
        SecTrustSetPolicies(serverTrust, policies as CFArray)

        var error: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &error) else {
            // Standard TLS validation failed — block connection
            AppLogger.error("Certificate validation failed: \(error?.localizedDescription ?? "unknown")")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Check if any certificate in chain matches our pinned hashes
        let certificateCount = SecTrustGetCertificateCount(serverTrust)

        // DoS protection: reject excessively deep certificate chains
        let maxCertificateChainDepth = 32
        guard certificateCount <= maxCertificateChainDepth else {
            AppLogger.warning("Rejected certificate chain with \(certificateCount) certificates (max: \(maxCertificateChainDepth))")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        var isPinned = false

        AppLogger.debug("Certificate pinning: checking \(certificateCount) certificates for \(challenge.protectionSpace.host)")

        for index in 0..<certificateCount {
            guard let certificate = SecTrustGetCertificateAtIndex(serverTrust, index) else { continue }

            if let publicKeyHash = getPublicKeyHash(for: certificate) {
                AppLogger.debug("Certificate[\(index)] hash: \(publicKeyHash)")
                if Constants.CertificatePinning.pinnedPublicKeyHashes.contains(publicKeyHash) {
                    isPinned = true
                    break
                }
            } else {
                AppLogger.debug("Certificate[\(index)] hash: failed to compute")
            }
        }

        if isPinned {
            AppLogger.debug("Certificate pinning succeeded for \(challenge.protectionSpace.host)")
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            // Graceful degradation: allow connection but warn user
            AppLogger.warning("Certificate pinning failed for \(challenge.protectionSpace.host) — allowing with warning")

            // Notify UI only once per session (thread-safe check-and-set)
            if Self.pinningState.setNotifiedIfNeeded() {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .certificatePinningFailed,
                        object: nil,
                        userInfo: ["host": challenge.protectionSpace.host]
                    )
                }
            }

            // Allow connection (TLS is still valid, just not pinned)
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        }
    }

    private func getPublicKeyHash(for certificate: SecCertificate) -> String? {
        guard let publicKey = SecCertificateCopyKey(certificate) else { return nil }

        var error: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            return nil
        }

        // Get the key type and size to determine correct ASN.1 header
        guard let keyAttributes = SecKeyCopyAttributes(publicKey) as? [String: Any],
              let keyType = keyAttributes[kSecAttrKeyType as String] as? String else {
            return nil
        }

        // Build SPKI (Subject Public Key Info) by prepending ASN.1 header
        // This matches what openssl outputs for public key hashes
        var spkiData = Data()

        if keyType == (kSecAttrKeyTypeRSA as String) {
            // RSA key - determine header based on key size
            let keySize = publicKeyData.count
            if keySize > 256 {
                // RSA 4096 bit key
                spkiData.append(contentsOf: Self.rsa4096SPKIHeader)
            } else {
                // RSA 2048 bit key (most common)
                spkiData.append(contentsOf: Self.rsa2048SPKIHeader)
            }
        } else if keyType == (kSecAttrKeyTypeECSECPrimeRandom as String) {
            // ECDSA key - P-256 is most common for TLS
            spkiData.append(contentsOf: Self.ecdsaSecp256r1SPKIHeader)
        } else {
            // Unknown key type - hash raw data as fallback
            AppLogger.warning("Unknown key type for certificate pinning: \(keyType)")
        }

        spkiData.append(publicKeyData)

        // SHA256 hash of SPKI
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        spkiData.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }

        return Data(hash).base64EncodedString()
    }

    // MARK: - ASN.1 SPKI Headers

    // RSA 2048 SPKI header (for keys ~256 bytes)
    private static let rsa2048SPKIHeader: [UInt8] = [
        0x30, 0x82, 0x01, 0x22,  // SEQUENCE, length 290
        0x30, 0x0D,              // SEQUENCE, length 13
        0x06, 0x09,              // OID, length 9
        0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01,  // rsaEncryption OID
        0x05, 0x00,              // NULL
        0x03, 0x82, 0x01, 0x0F,  // BIT STRING, length 271
        0x00                     // padding
    ]

    // RSA 4096 SPKI header (for keys ~512 bytes)
    private static let rsa4096SPKIHeader: [UInt8] = [
        0x30, 0x82, 0x02, 0x22,  // SEQUENCE, length 546
        0x30, 0x0D,              // SEQUENCE, length 13
        0x06, 0x09,              // OID, length 9
        0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01,  // rsaEncryption OID
        0x05, 0x00,              // NULL
        0x03, 0x82, 0x02, 0x0F,  // BIT STRING, length 527
        0x00                     // padding
    ]

    // ECDSA P-256 (secp256r1) SPKI header
    private static let ecdsaSecp256r1SPKIHeader: [UInt8] = [
        0x30, 0x59,              // SEQUENCE, length 89
        0x30, 0x13,              // SEQUENCE, length 19
        0x06, 0x07,              // OID, length 7
        0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01,  // ecPublicKey OID
        0x06, 0x08,              // OID, length 8
        0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07,  // secp256r1 OID
        0x03, 0x42,              // BIT STRING, length 66
        0x00                     // padding
    ]

    /// Resets pinning failure state (call on logout or app restart)
    static func resetPinningState() {
        pinningState.reset()
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
    let senderName: String?
    let senderAvatarURL: URL?
    let senderId: String?

    private static let linkPatternRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"href=["']([^"']+)["']"#, options: [])
    }()

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
            if parsedTitle?.isEmpty ?? true {
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
            if let regex = Self.linkPatternRegex,
               let match = regex.firstMatch(in: content, options: [], range: NSRange(location: 0, length: content.utf16.count)),
               let urlRange = Range(match.range(at: 1), in: content) {
                let urlString = String(content[urlRange])

                // Validate URL scheme for security (XSS/phishing protection)
                let allowedSchemes: Set<String> = ["http", "https"]

                if urlString.hasPrefix("/") {
                    // Relative URL - construct full URL using baseURL
                    // Note: This requires baseURL to be accessible in static context
                    // For now, skip relative URL construction to avoid hardcoding domain
                    if let url = URL(string: urlString) {
                        parsedLink = url
                    }
                } else if let url = URL(string: urlString),
                          let scheme = url.scheme?.lowercased(),
                          allowedSchemes.contains(scheme) {
                    // Only allow http/https schemes to prevent javascript:, data:, file: URIs
                    parsedLink = url
                    AppLogger.debug("Validated and accepted URL with scheme: \(scheme)")
                } else if let url = URL(string: urlString) {
                    AppLogger.warning("Blocked URL with unsafe scheme: \(url.scheme ?? "none")")
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
        self.size = container.decodeFlexibleInt(keys: ["size"], defaultValue: 0)
        
        // Parse type
        self.type = try? container.decodeFlexibleString(keys: ["type"], defaultValue: nil)
        
        // Parse sender name and avatar using NotificationParser
        let senderInfo = NotificationParser.parseSenderInfo(from: container)
        var parsedSenderName = senderInfo.name
        let parsedAvatarURL = senderInfo.avatarURL
        let parsedSenderId = senderInfo.id
        
        // Fallback: extract sender name from content if still missing
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
        
        // Debug logging for sender info parsing
        if parsedSenderName != nil || parsedAvatarURL != nil || parsedSenderId != nil {
            AppLogger.debug("Final sender info - Name: \(parsedSenderName ?? "nil"), ID: \(parsedSenderId ?? "nil"), Avatar: \(parsedAvatarURL?.absoluteString ?? "nil")")
        }
        
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
        // Try ISO formatters first
        if let date = isoFormatter.date(from: value) {
            return date
        }
        
        if let date = shortISOFormatter.date(from: value) {
            return date
        }
        
        // Try custom formatters
        if let date = noTimezoneFormatter.date(from: value) {
            return date
        }
        
        if let date = dateOnlyFormatter.date(from: value) {
            return date
        }
        
        if let date = standardFormatter.date(from: value) {
            return date
        }
        
        // Try timestamp
        if let timeInterval = TimeInterval(value) {
            return Date(timeIntervalSince1970: timeInterval)
        }
        
        return nil
    }
}

    