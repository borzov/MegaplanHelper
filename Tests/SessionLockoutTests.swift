import XCTest
@testable import MegaplanHepler

@MainActor
final class SessionLockoutTests: XCTestCase {
    private final class AuthCallCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        func increment() {
            lock.lock()
            value += 1
            lock.unlock()
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    override func tearDown() {
        URLProtocolMock.handler = nil
        super.tearDown()
    }

    func testThreeFailuresLockSignIn() async {
        let counter = AuthCallCounter()
        URLProtocolMock.handler = { request in
            XCTAssertTrue(request.url?.path.hasSuffix("/api/v3/auth/access_token") == true)
            counter.increment()
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(#"{"error":"unauthorized"}"#.utf8))
        }

        let api = MegaplanAPI(
            domain: "demo.megaplan.ru",
            token: nil,
            session: URLProtocolMock.makeSession()
        )
        let state = AppState(api: api, userDefaults: isolatedDefaults(), keychain: InMemoryKeychain())
        await state.signIn(domain: "demo.megaplan.ru", login: "a@b.co", password: "x")
        await state.signIn(domain: "demo.megaplan.ru", login: "a@b.co", password: "x")
        await state.signIn(domain: "demo.megaplan.ru", login: "a@b.co", password: "x")
        await state.signIn(domain: "demo.megaplan.ru", login: "a@b.co", password: "x")
        XCTAssertEqual(state.lastAuthError, .lockout)
        XCTAssertNotNil(state.lockoutState)
        XCTAssertEqual(counter.count, 3)
    }
}

private func isolatedDefaults() -> UserDefaults {
    let suiteName = "test-\(UUID().uuidString)"
    let suite = UserDefaults(suiteName: suiteName)!
    suite.removePersistentDomain(forName: suiteName)
    return suite
}
