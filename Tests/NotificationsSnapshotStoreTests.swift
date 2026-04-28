import XCTest
@testable import MegaplanHepler

final class NotificationsSnapshotStoreTests: XCTestCase {
    private var tempDirectory: URL!
    private var snapshotURL: URL!
    private var store: NotificationsSnapshotStore!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MegaplanSnapshotTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        snapshotURL = tempDirectory.appendingPathComponent("notifications_snapshot.json")
        store = NotificationsSnapshotStore(fileURL: snapshotURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        store = nil
        snapshotURL = nil
        tempDirectory = nil
    }

    func testSaveAndLoad_MatchingWorkspace_ReturnsSnapshot() async {
        let notification = MegaplanNotification(
            id: "n1",
            title: "Title",
            body: "Body",
            createdAt: Date(),
            link: nil,
            isRead: false
        )

        await store.save(workspaceKey: "acme.megaplan.ru", unreadCount: 3, notifications: [notification])
        let loaded = await store.load(workspaceKey: "acme.megaplan.ru")

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.workspaceKey, "acme.megaplan.ru")
        XCTAssertEqual(loaded?.unreadCount, 3)
        XCTAssertEqual(loaded?.notifications.count, 1)
        XCTAssertEqual(loaded?.notifications.first?.id, "n1")
    }

    func testLoad_DifferentWorkspace_ReturnsNil() async {
        await store.save(workspaceKey: "acme.megaplan.ru", unreadCount: 1, notifications: [])

        let loaded = await store.load(workspaceKey: "other.megaplan.ru")

        XCTAssertNil(loaded)
    }

    func testClear_RemovesSnapshotFile() async {
        await store.save(workspaceKey: "acme.megaplan.ru", unreadCount: 1, notifications: [])
        await store.clear()

        let loaded = await store.load(workspaceKey: "acme.megaplan.ru")
        XCTAssertNil(loaded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotURL.path))
    }

    func testLoad_ExpiredSnapshot_ReturnsNilAndClearsFile() async throws {
        let expired = NotificationsSnapshotEnvelope(
            schemaVersion: NotificationsSnapshotEnvelope.currentSchemaVersion,
            savedAt: Date().addingTimeInterval(-(Constants.SnapshotConfig.notificationsTTL + 1)),
            workspaceKey: "acme.megaplan.ru",
            unreadCount: 1,
            notifications: []
        )
        let data = try JSONEncoder().encode(expired)
        try data.write(to: snapshotURL, options: .atomic)

        let loaded = await store.load(workspaceKey: "acme.megaplan.ru")

        XCTAssertNil(loaded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotURL.path))
    }
}
