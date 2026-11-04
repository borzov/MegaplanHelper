import XCTest
@testable import MegaplanHepler

@MainActor
final class WorkspaceSyncTests: XCTestCase {
    private var tempDirectory: URL!
    private var tempURL: URL!
    private var session: URLSession!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceSyncTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        tempURL = tempDirectory.appendingPathComponent("notifications_snapshot.json")
        session = URLProtocolMock.makeSession()
        URLProtocolMock.handler = nil
    }

    override func tearDownWithError() throws {
        URLProtocolMock.handler = nil
        session = nil
        try? FileManager.default.removeItem(at: tempDirectory)
        tempURL = nil
        tempDirectory = nil
    }

    func testOfflineKeepsPreviousNotifications() async {
        let api = MegaplanAPI(domain: "demo.megaplan.ru", token: "t", session: session)
        let store = NotificationsSnapshotStore(fileURL: tempURL)
        let sync = WorkspaceSync(
            api: api,
            snapshotStore: store,
            poster: RecordingPoster(),
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            sleep: { _ in }
        )

        URLProtocolMock.handler = { _ in successNotifications(id: "a") }
        await sync.refresh()
        XCTAssertEqual(sync.notifications.map(\.id), ["a"])

        URLProtocolMock.handler = { request in
            throw URLError(.notConnectedToInternet)
        }
        await sync.refresh()
        XCTAssertEqual(sync.notifications.map(\.id), ["a"])
        XCTAssertTrue(sync.isOffline)
    }

    func testUnauthorizedStopsTheSession() async {
        // handler отвечает 401
        // sync.isSessionExpired == true, sync.isAuthenticated == false
        let sync = makeSync()
        sync.isAuthenticated = true
        URLProtocolMock.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        await sync.refresh()
        XCTAssertTrue(sync.isSessionExpired)
        XCTAssertFalse(sync.isAuthenticated)
    }

    func testMarkReadRollsBackWhenDeleteFails() async {
        // список из одного уведомления, DELETE отвечает 500
        // уведомление снова в списке, unreadCount восстановлен
        let sync = makeSync()
        URLProtocolMock.handler = { request in
            let path = request.url?.path ?? ""
            if path.contains("/counter") {
                let body = Data("{\"data\":{\"count\":1}}".utf8)
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, body)
            }
            return successNotifications(id: "only")
        }
        await sync.refresh()
        let before = sync.unreadCount
        guard let notification = sync.notifications.first else {
            XCTFail("Expected one notification before mark-read")
            return
        }

        URLProtocolMock.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data("fail".utf8))
        }
        await sync.markNotificationAsRead(notification)

        XCTAssertEqual(sync.notifications.map(\.id), ["only"])
        XCTAssertEqual(sync.unreadCount, before)
    }

    func testRetryThenSuccess() async {
        // два ответа 500, третий — конверт с одним уведомлением
        // sync.notifications.count == 1
        // запросов к notification больше двух
        let sync = makeSync()
        let counter = RequestCounter()
        URLProtocolMock.handler = { request in
            let path = request.url?.path ?? ""
            let isNotificationList = path.contains("/api/v3/notification") && !path.contains("counter")
            if isNotificationList {
                let attempt = counter.increment()
                if attempt <= 2 {
                    let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
                    return (response, Data("fail".utf8))
                }
                return successNotifications(id: "n1")
            }
            let body = Data("{\"data\":{\"count\":1}}".utf8)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }

        await sync.refresh()
        XCTAssertEqual(sync.notifications.count, 1)
        XCTAssertGreaterThan(counter.count, 2)
    }

    private func makeSync() -> WorkspaceSync {
        let api = MegaplanAPI(domain: "demo.megaplan.ru", token: "t", session: session)
        let store = NotificationsSnapshotStore(fileURL: tempURL)
        return WorkspaceSync(
            api: api,
            snapshotStore: store,
            poster: RecordingPoster(),
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            sleep: { _ in }
        )
    }
}

@MainActor
private final class RecordingPoster: NotificationPoster {
    private(set) var sentIDs: [String] = []

    func send(_ notification: MegaplanNotification) {
        sentIDs.append(notification.id)
    }
}

private func successNotifications(id: String) -> (HTTPURLResponse, Data?) {
    let url = URL(string: "https://demo.megaplan.ru/api/v3/notification")!
    let body = Data("{\"data\":[{\"id\":\"\(id)\",\"content\":\"text\"}]}".utf8)
    let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
    return (response, body)
}

private final class RequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
