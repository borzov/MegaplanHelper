import Foundation

struct NotificationGroup: Identifiable {
    let id: String
    let title: String
    let notifications: [MegaplanNotification]
    let date: Date
}

enum NotificationGrouper {
    static func group(_ notifications: [MegaplanNotification]) -> [NotificationGroup] {
        let calendar = Calendar.current
        let now = Date()
        
        var groups: [NotificationGroup] = []
        
        // Сегодня
        let today = calendar.startOfDay(for: now)
        let todayNotifications = notifications.filter { calendar.isDate($0.createdAt, inSameDayAs: now) }
        if !todayNotifications.isEmpty {
            groups.append(NotificationGroup(
                id: "today",
                title: String(localized: "notifications.group.today"),
                notifications: todayNotifications,
                date: today
            ))
        }
        
        // Вчера
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today) {
            let yesterdayNotifications = notifications.filter { calendar.isDate($0.createdAt, inSameDayAs: yesterday) }
            if !yesterdayNotifications.isEmpty {
                groups.append(NotificationGroup(
                    id: "yesterday",
                    title: String(localized: "notifications.group.yesterday"),
                    notifications: yesterdayNotifications,
                    date: yesterday
                ))
            }
        }
        
        // На этой неделе
        if let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) {
            let weekNotifications = notifications.filter { notification in
                let notificationDate = calendar.startOfDay(for: notification.createdAt)
                return notificationDate >= weekStart && notificationDate < today && !calendar.isDate(notification.createdAt, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: today) ?? today)
            }
            if !weekNotifications.isEmpty {
                groups.append(NotificationGroup(
                    id: "thisWeek",
                    title: String(localized: "notifications.group.thisWeek"),
                    notifications: weekNotifications,
                    date: weekStart
                ))
            }
        }
        
        // Ранее
        let earlierNotifications = notifications.filter { notification in
            let notificationDate = calendar.startOfDay(for: notification.createdAt)
            if let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) {
                return notificationDate < weekStart
            }
            return notificationDate < today
        }
        if !earlierNotifications.isEmpty {
            groups.append(NotificationGroup(
                id: "earlier",
                title: String(localized: "notifications.group.earlier"),
                notifications: earlierNotifications,
                date: Date.distantPast
            ))
        }
        
        return groups
    }
}

