import Foundation

struct AlertItem: Identifiable {
    let id = UUID()
    let message: String
}

struct NotificationsSnapshotEnvelope: Codable {
    static var currentSchemaVersion: Int { Constants.SnapshotConfig.notificationsSchemaVersion }

    let schemaVersion: Int
    let savedAt: Date
    let workspaceKey: String
    let unreadCount: Int
    let notifications: [MegaplanNotification]
}

actor NotificationsSnapshotStore {
    static let shared = NotificationsSnapshotStore()

    struct SnapshotStats {
        let sizeBytes: Int64
        let savedAt: Date
        let unreadCount: Int
        let notificationsCount: Int
    }

    private let fileURL: URL
    private let fileManager: FileManager
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(fileManager: FileManager = .default, fileURL: URL? = nil) {
        self.fileManager = fileManager
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let directoryURL = cachesURL
                .appendingPathComponent("MegaplanMenuBarApp", isDirectory: true)
                .appendingPathComponent("Snapshots", isDirectory: true)
            self.fileURL = directoryURL.appendingPathComponent("notifications_snapshot.json")
        }
    }

    func load(workspaceKey: String) -> NotificationsSnapshotEnvelope? {
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let snapshot = try? decoder.decode(NotificationsSnapshotEnvelope.self, from: data) else {
            return nil
        }

        guard snapshot.schemaVersion == NotificationsSnapshotEnvelope.currentSchemaVersion else {
            clear()
            return nil
        }

        let age = Date().timeIntervalSince(snapshot.savedAt)
        guard age <= Constants.SnapshotConfig.notificationsTTL else {
            clear()
            return nil
        }

        guard snapshot.workspaceKey == workspaceKey else {
            return nil
        }

        return snapshot
    }

    func save(workspaceKey: String, unreadCount: Int, notifications: [MegaplanNotification]) {
        let snapshot = NotificationsSnapshotEnvelope(
            schemaVersion: NotificationsSnapshotEnvelope.currentSchemaVersion,
            savedAt: Date(),
            workspaceKey: workspaceKey,
            unreadCount: unreadCount,
            notifications: notifications
        )

        do {
            let directoryURL = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            AppLogger.warning("Failed to save notifications snapshot: \(error.localizedDescription)")
        }
    }

    func clear() {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        do {
            try fileManager.removeItem(at: fileURL)
        } catch {
            AppLogger.warning("Failed to clear notifications snapshot: \(error.localizedDescription)")
        }
    }

    func snapshotStats(workspaceKey: String) -> SnapshotStats? {
        guard let snapshot = load(workspaceKey: workspaceKey),
              let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? NSNumber else {
            return nil
        }

        return SnapshotStats(
            sizeBytes: size.int64Value,
            savedAt: snapshot.savedAt,
            unreadCount: snapshot.unreadCount,
            notificationsCount: snapshot.notifications.count
        )
    }
}
