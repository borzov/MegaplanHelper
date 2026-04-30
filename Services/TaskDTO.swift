import Foundation

// MARK: - Envelope

struct TaskListEnvelope: Decodable {
    let items: [MegaplanTask]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)

        guard let dataKey = DynamicCodingKey(stringValue: "data"),
              let dtos = try? container.decode([TaskDTO].self, forKey: dataKey) else {
            self.items = []
            return
        }

        // Megaplan can return mixed Task/Project entities under `data` — keep only Task content type.
        self.items = dtos.compactMap { $0.contentType == "Task" ? $0.toDomain() : nil }
    }
}

// MARK: - Wrapped DateTime / DateOnly

/// Decodes Megaplan v3 DateTime envelope `{contentType: "DateTime", value: "ISO8601"}`.
struct MegaplanDateTime: Decodable {
    let value: Date

    enum CodingKeys: String, CodingKey {
        case contentType
        case value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode(String.self, forKey: .value)
        guard let parsed = DateParser.parse(raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: .value,
                in: container,
                debugDescription: "Cannot parse DateTime value: \(raw)"
            )
        }
        self.value = parsed
    }
}

/// Decodes Megaplan v3 DateOnly envelope `{contentType: "DateOnly", year, month, day}`.
struct MegaplanDateOnly: Decodable {
    let value: Date

    enum CodingKeys: String, CodingKey {
        case contentType, year, month, day
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let year = try container.decode(Int.self, forKey: .year)
        let month = try container.decode(Int.self, forKey: .month)
        let day = try container.decode(Int.self, forKey: .day)

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 0
        components.minute = 0
        components.second = 0

        let calendar = Calendar.current
        guard let date = calendar.date(from: components) else {
            throw DecodingError.dataCorruptedError(
                forKey: .year,
                in: container,
                debugDescription: "Cannot build Date from \(year)-\(month)-\(day)"
            )
        }
        self.value = date
    }
}

// MARK: - DTO

struct TaskDTO: Decodable {
    let contentType: String
    let id: String
    let name: String
    let status: String?
    let responsible: ParticipantDTO?
    let owner: ParticipantDTO?
    let auditors: [ParticipantDTO]
    let executors: [ParticipantDTO]
    let timeCreated: MegaplanDateTime?
    let activity: MegaplanDateTime?
    let lastCommentTimeCreated: MegaplanDateTime?
    let totalCommentsCount: Int
    let unreadCommentsCount: Int
    let humanNumber: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        self.contentType = (try? container.decodeFlexibleString(keys: ["contentType"], defaultValue: "Task")) ?? "Task"
        self.id = (try? container.decodeFlexibleString(keys: ["id"], defaultValue: "")) ?? ""
        self.name = (try? container.decodeFlexibleString(keys: ["name", "subject", "title"], defaultValue: "")) ?? ""
        self.status = try? container.decodeFlexibleString(keys: ["status"], defaultValue: nil)
        self.responsible = TaskDTO.decodeParticipant(container: container, key: "responsible")
        self.owner = TaskDTO.decodeParticipant(container: container, key: "owner")
        self.auditors = TaskDTO.decodeParticipantArray(container: container, key: "auditors")
        self.executors = TaskDTO.decodeParticipantArray(container: container, key: "executors")
        self.timeCreated = TaskDTO.decodeDateTime(container: container, key: "timeCreated")
        self.activity = TaskDTO.decodeDateTime(container: container, key: "activity")
        self.lastCommentTimeCreated = TaskDTO.decodeDateTime(container: container, key: "lastCommentTimeCreated")
        self.totalCommentsCount = container.decodeFlexibleInt(keys: ["commentsCount"], defaultValue: 0)
        self.unreadCommentsCount = container.decodeFlexibleInt(keys: ["unreadCommentsCount"], defaultValue: 0)
        if let value = try? container.decodeFlexibleString(keys: ["humanNumber"], defaultValue: nil),
           let intValue = Int(value) {
            self.humanNumber = intValue
        } else {
            self.humanNumber = nil
        }
    }

    func toDomain() -> MegaplanTask {
        MegaplanTask(
            id: id,
            name: name,
            status: TaskStatus.parse(status),
            responsible: responsible?.toDomain(),
            owner: owner?.toDomain(),
            auditors: auditors.map { $0.toDomain() },
            executors: executors.map { $0.toDomain() },
            timeCreated: timeCreated?.value ?? .distantPast,
            activity: activity?.value,
            lastCommentTimeCreated: lastCommentTimeCreated?.value,
            totalCommentsCount: totalCommentsCount,
            unreadCommentsCount: unreadCommentsCount,
            humanNumber: humanNumber
        )
    }

    private static func decodeParticipant(container: KeyedDecodingContainer<DynamicCodingKey>, key: String) -> ParticipantDTO? {
        guard let codingKey = DynamicCodingKey(stringValue: key) else { return nil }
        return try? container.decode(ParticipantDTO.self, forKey: codingKey)
    }

    private static func decodeParticipantArray(container: KeyedDecodingContainer<DynamicCodingKey>, key: String) -> [ParticipantDTO] {
        guard let codingKey = DynamicCodingKey(stringValue: key) else { return [] }
        return (try? container.decode([ParticipantDTO].self, forKey: codingKey)) ?? []
    }

    private static func decodeDateTime(container: KeyedDecodingContainer<DynamicCodingKey>, key: String) -> MegaplanDateTime? {
        guard let codingKey = DynamicCodingKey(stringValue: key) else { return nil }
        return try? container.decode(MegaplanDateTime.self, forKey: codingKey)
    }
}

struct ParticipantDTO: Decodable {
    let contentType: String
    let id: String
    let name: String
    let avatarURL: URL?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        self.contentType = (try? container.decodeFlexibleString(keys: ["contentType"], defaultValue: "Employee")) ?? "Employee"
        self.id = (try? container.decodeFlexibleString(keys: ["id"], defaultValue: "")) ?? ""
        self.name = (try? container.decodeFlexibleString(keys: ["name"], defaultValue: "")) ?? ""
        self.avatarURL = ParticipantDTO.extractAvatarURL(container: container)
    }

    func toDomain() -> TaskParticipant {
        TaskParticipant(id: id, contentType: contentType, name: name, avatarURL: avatarURL)
    }

    private static func extractAvatarURL(container: KeyedDecodingContainer<DynamicCodingKey>) -> URL? {
        // Avatar may live as `avatar.url`, `avatar.link`, or directly as `avatarUrl`.
        if let direct = container.decodeFlexibleURL(keys: ["avatarUrl"]) {
            return direct
        }
        guard let avatarKey = DynamicCodingKey(stringValue: "avatar"),
              let nested = try? container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: avatarKey) else {
            return nil
        }
        if let url = nested.decodeFlexibleURL(keys: ["url", "link", "src"]) {
            return url
        }
        // Some endpoints return avatar as `{contentType: "File", thumbnail: {url:...}}`.
        if let thumbnailKey = DynamicCodingKey(stringValue: "thumbnail"),
           let thumbnailContainer = try? nested.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: thumbnailKey),
           let url = thumbnailContainer.decodeFlexibleURL(keys: ["url", "link"]) {
            return url
        }
        return nil
    }
}
