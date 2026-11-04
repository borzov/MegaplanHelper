import XCTest
@testable import MegaplanHepler

@MainActor
final class SessionCredentialTests: XCTestCase {
    override func tearDown() {
        URLProtocolMock.handler = nil
        super.tearDown()
    }

    func testLogoutDropsStoredCredential() async {
        URLProtocolMock.handler = Self.successHandler
        let state = AppState(
            api: MegaplanAPI(domain: "demo.megaplan.ru", token: nil, session: URLProtocolMock.makeSession()),
            userDefaults: isolatedCredentialDefaults(),
            keychain: InMemoryKeychain()
        )
        await state.signIn(domain: "demo.megaplan.ru", login: "a@b.co", password: "secret")
        XCTAssertTrue(state.isAuthenticated)
        XCTAssertTrue(state.api.hasCredential)

        await state.logout()

        let running = await state.refreshScheduler.getIsRunning()
        XCTAssertFalse(state.api.hasCredential)
        XCTAssertFalse(running)
    }

    func testUnauthorizedRefreshDropsCredentialAndStopsTimer() async {
        URLProtocolMock.handler = Self.unauthorizedAfterSignInHandler
        let state = AppState(
            api: MegaplanAPI(domain: "demo.megaplan.ru", token: nil, session: URLProtocolMock.makeSession()),
            userDefaults: isolatedCredentialDefaults(),
            keychain: InMemoryKeychain()
        )

        await state.signIn(domain: "demo.megaplan.ru", login: "a@b.co", password: "secret")

        let running = await state.refreshScheduler.getIsRunning()
        XCTAssertFalse(state.api.hasCredential)
        XCTAssertFalse(state.isAuthenticated)
        XCTAssertFalse(running)
    }

    private static func successHandler(_ request: URLRequest) throws -> (HTTPURLResponse, Data?) {
        let path = request.url?.path ?? ""
        let url = request.url ?? URL(string: "https://demo.megaplan.ru/")!
        if path.hasSuffix("/api/v3/auth/access_token") {
            return http(url, status: 200, body: #"{"access_token":"token-1"}"#)
        }
        if path.hasSuffix("/notification/counter") {
            return http(url, status: 200, body: #"{"data":{"count":0}}"#)
        }
        if path.contains("/notification") {
            return http(url, status: 200, body: #"{"data":[]}"#)
        }
        return http(url, status: 200, body: #"{"data":{"id":"7","firstName":"Максим","notificationsUnreadCount":0}}"#)
    }

    private static func unauthorizedAfterSignInHandler(_ request: URLRequest) throws -> (HTTPURLResponse, Data?) {
        let path = request.url?.path ?? ""
        let url = request.url ?? URL(string: "https://demo.megaplan.ru/")!
        if path.hasSuffix("/api/v3/auth/access_token") {
            return http(url, status: 200, body: #"{"access_token":"token-1"}"#)
        }
        if path.hasSuffix("/api/v3/currentUser") {
            return http(url, status: 200, body: #"{"data":{"id":"7","firstName":"Максим","notificationsUnreadCount":0}}"#)
        }
        return http(url, status: 401, body: #"{"error":"unauthorized"}"#)
    }

    private static func http(_ url: URL, status: Int, body: String) -> (HTTPURLResponse, Data?) {
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (response, Data(body.utf8))
    }
}

private func isolatedCredentialDefaults() -> UserDefaults {
    let suiteName = "credential-test-\(UUID().uuidString)"
    let suite = UserDefaults(suiteName: suiteName)!
    suite.removePersistentDomain(forName: suiteName)
    return suite
}
