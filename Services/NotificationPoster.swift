import Foundation

/// Шов между обновлением ленты и системными баннерами.
/// Боевой адаптер зовёт сегодняшний `NotificationManager`, тесты подставляют запись id.
@MainActor
protocol NotificationPoster {
    func send(_ notification: MegaplanNotification)
}

@MainActor
struct NotificationManagerPoster: NotificationPoster {
    func send(_ notification: MegaplanNotification) {
        NotificationManager.shared.sendNotification(for: notification)
    }
}
