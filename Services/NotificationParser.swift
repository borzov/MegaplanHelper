import Foundation

struct NotificationParser {
    // MARK: - Sender Info Parser
    
    /// Парсит информацию об отправителе из JSON контейнера
    /// - Parameter container: JSON контейнер с данными уведомления
    /// - Returns: Tuple с именем, URL аватара и ID отправителя
    static func parseSenderInfo(from container: KeyedDecodingContainer<DynamicCodingKey>) -> (name: String?, avatarURL: URL?, id: String?) {
        var parsedSenderName: String?
        var parsedAvatarURL: URL?
        var parsedSenderId: String?
        
        // Try multiple possible sender keys
        let senderKeys = ["sender", "from", "author", "user", "employee", "actor", "creator"]
        
        for senderKeyName in senderKeys {
            if let key = DynamicCodingKey(stringValue: senderKeyName),
               let senderContainer = try? container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: key) {
                
                AppLogger.debug("Found sender container in key: \(senderKeyName)")
                
                // Parse ID
                if parsedSenderId == nil {
                    parsedSenderId = try? senderContainer.decodeFlexibleString(keys: ["id", "userId", "employeeId"], defaultValue: nil)
                }
                
                // Parse name
                if parsedSenderName == nil {
                    parsedSenderName = parseName(from: senderContainer)
                }
                
                // Parse avatar
                if parsedAvatarURL == nil {
                    parsedAvatarURL = parseAvatar(from: senderContainer)
                }
                
                // If we found everything, break early
                if parsedSenderId != nil && parsedSenderName != nil && parsedAvatarURL != nil {
                    AppLogger.debug("Found all sender info in key: \(senderKeyName)")
                    break
                }
            }
        }
        
        // Fallback to root level if anything is missing
        if parsedSenderId == nil || parsedSenderName == nil || parsedAvatarURL == nil {
            let rootInfo = parseSenderInfoFromRoot(container: container)
            parsedSenderId = parsedSenderId ?? rootInfo.id
            parsedSenderName = parsedSenderName ?? rootInfo.name
            parsedAvatarURL = parsedAvatarURL ?? rootInfo.avatarURL
            
            if rootInfo.id != nil || rootInfo.name != nil || rootInfo.avatarURL != nil {
                AppLogger.debug("Found additional sender info at root level")
            }
        }
        
        if parsedSenderName != nil || parsedAvatarURL != nil || parsedSenderId != nil {
            AppLogger.debug("Parsed sender - ID: \(parsedSenderId ?? "nil"), Name: \(parsedSenderName ?? "nil"), Avatar: \(parsedAvatarURL?.absoluteString ?? "nil")")
        }
        
        return (parsedSenderName, parsedAvatarURL, parsedSenderId)
    }
    
    // MARK: - Private Helpers
    
    private static func parseName(from container: KeyedDecodingContainer<DynamicCodingKey>) -> String? {
        // Try direct name field
        if let name = try? container.decodeFlexibleString(keys: ["name", "fullName", "displayName"], defaultValue: nil),
           !name.isEmpty {
            return name
        }
        
        // Try firstName + lastName combinations
        let firstName = try? container.decodeFlexibleString(keys: ["firstName", "first_name", "givenName"], defaultValue: nil)
        let lastName = try? container.decodeFlexibleString(keys: ["lastName", "last_name", "surname", "familyName"], defaultValue: nil)
        
        if let firstName = firstName, !firstName.isEmpty,
           let lastName = lastName, !lastName.isEmpty {
            return "\(lastName) \(firstName)"
        } else if let firstName = firstName, !firstName.isEmpty {
            return firstName
        } else if let lastName = lastName, !lastName.isEmpty {
            return lastName
        }
        
        return nil
    }
    
    private static func parseAvatar(from container: KeyedDecodingContainer<DynamicCodingKey>) -> URL? {
        // Try nested avatar object
        if let avatarKey = DynamicCodingKey(stringValue: "avatar"),
           let avatarContainer = try? container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: avatarKey) {
            
            // Try thumbnail with size replacement
            if let thumbnail = try? avatarContainer.decodeFlexibleString(keys: ["thumbnail", "thumb", "small"], defaultValue: nil),
               !thumbnail.isEmpty {
                let avatarURLString = thumbnail.replacingOccurrences(of: "{width}x{height}", with: "64x64")
                AppLogger.debug("Parsed avatar thumbnail: \(thumbnail) -> \(avatarURLString)")
                if avatarURLString.hasPrefix("//") {
                    let finalURL = URL(string: "https:\(avatarURLString)")
                    AppLogger.debug("Created avatar URL from // prefix: \(finalURL?.absoluteString ?? "nil")")
                    return finalURL
                } else if let url = URL(string: avatarURLString) {
                    AppLogger.debug("Created avatar URL: \(url.absoluteString)")
                    return url
                } else {
                    AppLogger.debug("Failed to create URL from avatar string: \(avatarURLString)")
                }
            }
            
            // Try path or URL
            if let path = try? avatarContainer.decodeFlexibleString(keys: ["path", "url", "href"], defaultValue: nil),
               !path.isEmpty {
                if path.hasPrefix("//") {
                    return URL(string: "https:\(path)")
                } else {
                    return URL(string: path)
                }
            }
        }
        
        // Try direct avatar field
        if let avatarString = try? container.decodeFlexibleString(keys: ["avatar", "avatarUrl", "avatarURL", "photo", "picture", "image"], defaultValue: nil),
           !avatarString.isEmpty {
            if avatarString.hasPrefix("//") {
                return URL(string: "https:\(avatarString)")
            } else {
                return URL(string: avatarString)
            }
        }
        
        return nil
    }
    
    private static func parseSenderInfoFromRoot(container: KeyedDecodingContainer<DynamicCodingKey>) -> (name: String?, avatarURL: URL?, id: String?) {
        let id = try? container.decodeFlexibleString(keys: ["senderId", "userId", "fromUserId", "authorId", "creatorId"], defaultValue: nil)
        let name = parseName(from: container)
        let avatarURL = parseAvatar(from: container)
        
        return (name, avatarURL, id)
    }
    
    // MARK: - Dictionary-based Extractors (for raw JSON parsing)
    
    /// Извлекает имя пользователя из словаря [String: Any]
    /// - Parameter dict: Словарь с данными пользователя
    /// - Returns: Имя пользователя или nil
    static func extractName(from dict: [String: Any]) -> String? {
        // Try direct name field
        if let name = dict["name"] as? String, !name.isEmpty {
            return name
        }
        
        // Try firstName + lastName combinations
        let firstName = dict["firstName"] as? String
        let lastName = dict["lastName"] as? String
        
        if let firstName = firstName, !firstName.isEmpty,
           let lastName = lastName, !lastName.isEmpty {
            return "\(lastName) \(firstName)"
        } else if let firstName = firstName, !firstName.isEmpty {
            return firstName
        } else if let lastName = lastName, !lastName.isEmpty {
            return lastName
        }
        
        return nil
    }
    
    /// Извлекает URL аватара из словаря [String: Any]
    /// - Parameter dict: Словарь с данными пользователя
    /// - Returns: URL аватара или nil
    static func extractAvatarURL(from dict: [String: Any]) -> URL? {
        // Try nested avatar object
        if let avatar = dict["avatar"] as? [String: Any] {
            // Try thumbnail with size replacement
            if let thumbnail = avatar["thumbnail"] as? String, !thumbnail.isEmpty {
                let avatarURLString = thumbnail.replacingOccurrences(of: "{width}x{height}", with: "64x64")
                AppLogger.debug("Parsed avatar thumbnail from dict: \(thumbnail) -> \(avatarURLString)")
                if avatarURLString.hasPrefix("//") {
                    let finalURL = URL(string: "https:\(avatarURLString)")
                    AppLogger.debug("Created avatar URL from // prefix: \(finalURL?.absoluteString ?? "nil")")
                    return finalURL
                } else if let url = URL(string: avatarURLString) {
                    AppLogger.debug("Created avatar URL: \(url.absoluteString)")
                    return url
                } else {
                    AppLogger.debug("Failed to create URL from avatar string: \(avatarURLString)")
                }
            }
            
            // Try path or URL
            if let path = avatar["path"] as? String, !path.isEmpty {
                if path.hasPrefix("//") {
                    return URL(string: "https:\(path)")
                } else {
                    return URL(string: path)
                }
            }
        }
        
        // Try direct avatar field
        if let avatarString = dict["avatar"] as? String, !avatarString.isEmpty {
            if avatarString.hasPrefix("//") {
                return URL(string: "https:\(avatarString)")
            } else {
                return URL(string: avatarString)
            }
        }
        
        return nil
    }
    
    // MARK: - Content Parser

    /// Cached regex patterns for sender name extraction
    private static let namePatterns: [(regex: NSRegularExpression, action: String)] = {
        let patterns: [(pattern: String, action: String)] = [
            // Russian patterns
            (#"([А-ЯЁ][а-яё]+(?:\s+[А-ЯЁ][а-яё]+){1,3})\s+написал"#, "написал"),
            (#"([А-ЯЁ][а-яё]+(?:\s+[А-ЯЁ][а-яё]+){1,3})\s+назначил"#, "назначил"),
            (#"([А-ЯЁ][а-яё]+(?:\s+[А-ЯЁ][а-яё]+){1,3})\s+добавил"#, "добавил"),
            (#"([А-ЯЁ][а-яё]+(?:\s+[А-ЯЁ][а-яё]+){1,3})\s+изменил"#, "изменил"),
            (#"([А-ЯЁ][а-яё]+(?:\s+[А-ЯЁ][а-яё]+){1,3})\s+создал"#, "создал"),

            // English patterns
            (#"([A-Z][a-z]+(?:\s+[A-Z][a-z]+){1,3})\s+wrote"#, "wrote"),
            (#"([A-Z][a-z]+(?:\s+[A-Z][a-z]+){1,3})\s+assigned"#, "assigned"),
            (#"([A-Z][a-z]+(?:\s+[A-Z][a-z]+){1,3})\s+added"#, "added"),
            (#"([A-Z][a-z]+(?:\s+[A-Z][a-z]+){1,3})\s+created"#, "created"),

            // Mixed patterns (Cyrillic + Latin)
            (#"([A-ZА-ЯЁ][a-zа-яё]+(?:\s+[A-ZА-ЯЁ][a-zа-яё]+){1,3})\s+написал"#, "написал"),
            (#"([A-ZА-ЯЁ][a-zа-яё]+(?:\s+[A-ZА-ЯЁ][a-zа-яё]+){1,3})\s+назначил"#, "назначил"),
        ]

        return patterns.compactMap { pattern, action in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
                AppLogger.warning("Failed to compile regex pattern: \(pattern)")
                return nil
            }
            return (regex, action)
        }
    }()

    /// Извлекает имя отправителя из текста уведомления
    /// - Parameter content: HTML контент уведомления
    /// - Returns: Извлеченное имя или nil
    static func extractSenderNameFromContent(_ content: String) -> String? {
        for (regex, action) in namePatterns {
            if let match = regex.firstMatch(in: content, options: [], range: NSRange(location: 0, length: content.utf16.count)),
               match.numberOfRanges > 1,
               let nameRange = Range(match.range(at: 1), in: content) {
                let extractedName = String(content[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                let nameComponents = extractedName.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

                // Validate name has 2-4 words (first name + last name, possibly with middle name)
                if nameComponents.count >= 2 && nameComponents.count <= 4 {
                    AppLogger.debug("Extracted sender name from content: \(extractedName) (action: \(action))")
                    return extractedName
                }
            }
        }

        return nil
    }
}

