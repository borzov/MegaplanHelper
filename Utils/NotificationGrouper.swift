import Foundation

struct NotificationGroup: Identifiable {
    let id: String
    let title: String
    let notifications: [MegaplanNotification]
    let date: Date
}

enum NotificationGrouper {
    /// Cached Calendar instance to avoid repeated creation
    private static let calendar = Calendar.current

    static func group(_ notifications: [MegaplanNotification]) -> [NotificationGroup] {
        guard !notifications.isEmpty else { return [] }

        let now = Date()

        // Pre-compute date boundaries once with safe fallbacks
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today

        // Safely compute week start - fallback to 7 days ago if dateComponents fails
        let weekStart: Date = {
            if let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) {
                return start
            }
            // Fallback: use 7 days ago as week start
            return calendar.date(byAdding: .day, value: -7, to: today) ?? today
        }()

        // Pre-compute notification dates to avoid repeated startOfDay calls
        let notificationsWithDates = notifications.map { notification in
            (notification: notification, dayStart: calendar.startOfDay(for: notification.createdAt))
        }

        // Group notifications in a single pass
        var todayNotifications: [MegaplanNotification] = []
        var yesterdayNotifications: [MegaplanNotification] = []
        var weekNotifications: [MegaplanNotification] = []
        var earlierNotifications: [MegaplanNotification] = []

        for item in notificationsWithDates {
            if item.dayStart >= today {
                todayNotifications.append(item.notification)
            } else if item.dayStart >= yesterday {
                yesterdayNotifications.append(item.notification)
            } else if item.dayStart >= weekStart {
                weekNotifications.append(item.notification)
            } else {
                earlierNotifications.append(item.notification)
            }
        }

        // Build groups
        var groups: [NotificationGroup] = []

        if !todayNotifications.isEmpty {
            groups.append(NotificationGroup(
                id: "today",
                title: String(localized: "notifications.group.today"),
                notifications: todayNotifications,
                date: today
            ))
        }

        if !yesterdayNotifications.isEmpty {
            groups.append(NotificationGroup(
                id: "yesterday",
                title: String(localized: "notifications.group.yesterday"),
                notifications: yesterdayNotifications,
                date: yesterday
            ))
        }

        if !weekNotifications.isEmpty {
            groups.append(NotificationGroup(
                id: "thisWeek",
                title: String(localized: "notifications.group.thisWeek"),
                notifications: weekNotifications,
                date: weekStart
            ))
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

