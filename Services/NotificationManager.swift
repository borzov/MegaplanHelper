import Foundation
import UserNotifications

@MainActor
final class NotificationManager {
    static let shared = NotificationManager()
    
    private let userDefaults: UserDefaults
    private let sentNotificationsKey = "sentNotificationIDs"
    private var sentNotificationIDs: Set<String> = []
    
    private init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        loadSentNotificationIDs()
    }
    
    /// Запрашивает разрешение на отправку уведомлений
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            AppLogger.info("Notification authorization granted: \(granted)")
            return granted
        } catch {
            AppLogger.error("Failed to request notification authorization: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Проверяет текущий статус разрешения
    func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }
    
    /// Отправляет уведомление для нового непрочитанного уведомления
    func sendNotification(for notification: MegaplanNotification) {
        // Проверяем, включены ли системные уведомления
        let notificationsEnabled = UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.notificationsEnabled) as? Bool ?? true
        guard notificationsEnabled else {
            AppLogger.debug("System notifications disabled, skipping")
            return
        }
        
        // Проверяем, не было ли уже отправлено уведомление для этого ID
        guard !sentNotificationIDs.contains(notification.id) else {
            AppLogger.debug("Notification \(notification.id) already sent, skipping")
            return
        }
        
        // Проверяем, что уведомление непрочитано
        guard !notification.isRead else {
            AppLogger.debug("Notification \(notification.id) is already read, skipping")
            return
        }
        
        Task {
            // Проверяем разрешение перед отправкой
            let status = await checkAuthorizationStatus()
            guard status == .authorized else {
                AppLogger.debug("Notification authorization not granted, status: \(status.rawValue)")
                return
            }
            
            let content = UNMutableNotificationContent()
            
            // Заголовок уведомления
            if !notification.title.isEmpty {
                content.title = notification.title
            } else {
                content.title = String(localized: "notifications.untitled")
            }
            
            // Тело уведомления
            if !notification.body.isEmpty {
                content.body = notification.body
            } else if !notification.title.isEmpty {
                content.body = notification.title
            } else {
                content.body = String(localized: "notifications.untitled")
            }
            
            // Звук
            content.sound = .default
            
            // Badge с количеством непрочитанных
            // Badge будет обновляться автоматически при обновлении счетчика
            
            // User info для идентификации уведомления
            content.userInfo = [
                "notificationID": notification.id,
                "link": notification.link?.absoluteString ?? ""
            ]
            
            // Создаем запрос на уведомление
            let request = UNNotificationRequest(
                identifier: notification.id,
                content: content,
                trigger: nil // Немедленная отправка
            )
            
            do {
                try await UNUserNotificationCenter.current().add(request)
                
                // Сохраняем ID отправленного уведомления
                sentNotificationIDs.insert(notification.id)
                saveSentNotificationIDs()
                
                AppLogger.info("Sent notification for \(notification.id)")
            } catch {
                AppLogger.error("Failed to send notification: \(error.localizedDescription)")
            }
        }
    }
    
    /// Очищает список отправленных уведомлений (можно вызывать периодически)
    func clearOldSentNotifications(keepingLast count: Int = 100) {
        // Оставляем только последние N ID
        if sentNotificationIDs.count > count {
            let array = Array(sentNotificationIDs)
            sentNotificationIDs = Set(array.suffix(count))
            saveSentNotificationIDs()
            AppLogger.debug("Cleared old sent notification IDs, keeping \(count)")
        }
    }
    
    /// Очищает все отправленные уведомления
    func clearAllSentNotifications() {
        sentNotificationIDs.removeAll()
        saveSentNotificationIDs()
        AppLogger.debug("Cleared all sent notification IDs")
    }
    
    /// Загружает список отправленных уведомлений из UserDefaults
    private func loadSentNotificationIDs() {
        if let array = userDefaults.array(forKey: sentNotificationsKey) as? [String] {
            sentNotificationIDs = Set(array)
            AppLogger.debug("Loaded \(sentNotificationIDs.count) sent notification IDs")
        }
    }
    
    /// Сохраняет список отправленных уведомлений в UserDefaults
    private func saveSentNotificationIDs() {
        userDefaults.set(Array(sentNotificationIDs), forKey: sentNotificationsKey)
    }
}



