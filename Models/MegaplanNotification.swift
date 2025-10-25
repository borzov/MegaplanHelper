import Foundation

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
    
    var notificationIcon: String {
        guard let type = type else { return "bell" }
        
        if type.contains("Task") {
            return "checkmark.circle"
        } else if type.contains("Deal") {
            return "briefcase"
        } else if type.contains("Comment") {
            return "bubble.left"
        } else if type.contains("Status") {
            return "arrow.triangle.2.circlepath"
        } else {
            return "bell"
        }
    }

    var displayDate: String {
        Self.displayFormatter.string(from: createdAt)
    }

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale.autoupdatingCurrent
        return formatter
    }()

    init(id: String, title: String, body: String, createdAt: Date, link: URL?, isRead: Bool, isMention: Bool = false, unreadCommentsCount: Int = 0, size: Int = 0, type: String? = nil) {
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
        unreadCommentsCount: 3
    )
}
