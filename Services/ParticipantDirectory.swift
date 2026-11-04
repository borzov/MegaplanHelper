import Foundation

struct ParticipantSeed: Equatable {
    let id: String
    let name: String?
    let avatarURL: URL?
}

/// Reads participants out of raw JSON and returns seeds. Does not write the cache;
/// `UserInfoResolver.remember` is the only writer.
enum ParticipantDirectory {
    static func seeds(fromNotificationJSON data: Data) -> [ParticipantSeed] {
        guard let rows = rows(in: data) else { return [] }
        var acc = SeedAccumulator()
        for row in rows {
            if let sender = row["sender"] as? [String: Any] {
                acc.addPerson(sender)
            }
            if let subject = row["subject"] as? [String: Any] {
                acc.addSubject(subject)
            }
        }
        return acc.seeds
    }

    static func seeds(fromTaskJSON data: Data) -> [ParticipantSeed] {
        guard let rows = rows(in: data) else { return [] }
        var acc = SeedAccumulator()
        for task in rows {
            acc.addTask(task)
            for key in ["auditors", "executors", "participants"] {
                acc.addEach(task[key])
            }
        }
        return acc.seeds
    }

    /// Parsed notifications: only a sender that already has both a name and an avatar.
    /// A name lifted from body text, with no picture, is left out.
    static func seeds(fromParsed notifications: [MegaplanNotification]) -> [ParticipantSeed] {
        notifications.compactMap { notification in
            guard let id = notification.senderId, !id.isEmpty,
                  let name = notification.senderName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty,
                  let avatarURL = notification.senderAvatarURL else {
                return nil
            }
            return ParticipantSeed(id: id, name: name, avatarURL: avatarURL)
        }
    }

    /// The four avatar URLs the notification row used to probe, including `size=64x64`.
    /// `URL.path` drops that query, so callers must keep it themselves.
    static func fallbackAvatarPaths(userId: String) -> [URL] {
        [
            "/api/v3/user/\(userId)/avatar/thumbnail?size=64x64",
            "/api/v3/user/\(userId)/avatar",
            "/api/v3/employee/\(userId)/avatar/thumbnail?size=64x64",
            "/BumsCommonBundle/images/personal/noavatar_64x64.jpg"
        ].compactMap { URL(string: $0) }
    }

    private static func rows(in data: Data) -> [[String: Any]]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["data"] as? [[String: Any]]
    }

    fileprivate static func participantID(_ raw: Any?) -> String? {
        if let id = raw as? String {
            return id.isEmpty ? nil : id
        }
        if let id = raw as? Int {
            return String(id)
        }
        return nil
    }
}

private struct SeedAccumulator {
    private var byID: [String: ParticipantSeed] = [:]
    private var order: [String] = []

    var seeds: [ParticipantSeed] {
        order.compactMap { byID[$0] }
    }

    mutating func addPerson(_ raw: Any?) {
        guard let dict = raw as? [String: Any],
              let id = ParticipantDirectory.participantID(dict["id"]) else {
            return
        }
        let name = NotificationParser.extractName(from: dict).flatMap(Self.nonEmpty)
        let avatarURL = NotificationParser.extractAvatarURL(from: dict)
        // Имени без аватара достаточно: картинку потом доберёт резолвер.
        guard name != nil || avatarURL != nil else { return }
        let prior = byID[id]
        if prior == nil {
            order.append(id)
        }
        byID[id] = ParticipantSeed(
            id: id,
            name: name ?? prior?.name,
            avatarURL: avatarURL ?? prior?.avatarURL
        )
    }

    mutating func addEach(_ raw: Any?) {
        guard let people = raw as? [[String: Any]] else { return }
        for person in people {
            addPerson(person)
        }
    }

    mutating func addTask(_ task: [String: Any]) {
        addPerson(task["owner"])
        addPerson(task["responsible"])
    }

    mutating func addDeal(_ deal: [String: Any]) {
        addPerson(deal["manager"])
    }

    mutating func addSubject(_ subject: [String: Any]) {
        let type = subject["contentType"] as? String
        if type == "Task" {
            addTask(subject)
        }
        if type == "Deal" {
            addDeal(subject)
        }
        guard type == "Comment",
              let nested = subject["subject"] as? [String: Any] else {
            return
        }
        let nestedType = nested["contentType"] as? String
        if nestedType == "Task" {
            addTask(nested)
        }
        if nestedType == "Deal" {
            addDeal(nested)
        }
    }

    private static func nonEmpty(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
