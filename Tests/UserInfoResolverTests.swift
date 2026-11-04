import XCTest
@testable import MegaplanHepler

final class UserInfoResolverTests: XCTestCase {
    private var session: URLSession!

    override func setUpWithError() throws {
        session = URLProtocolMock.makeSession()
        URLProtocolMock.handler = nil
    }

    override func tearDown() async throws {
        await UserInfoResolver.shared.setImageProbe(nil)
        await UserInfoResolver.shared.configure(
            api: MegaplanAPI(),
            tokenProvider: { nil },
            domainProvider: { "" }
        )
        URLProtocolMock.handler = nil
        session = nil
    }

    func testNameWithoutAvatarIsAHitAndDoesNotFetchEmployee() async {
        let id = "cache-hit-\(UUID().uuidString)"
        await UserInfoCache.shared.cacheUserInfo(userId: id, name: "Иван", avatarURL: nil)
        let fetches = HitCounter()
        installEmployeeCounter(fetches, id: id)
        await configureResolver(token: "secret")

        let resolved = await UserInfoResolver.shared.resolve(id: id)

        XCTAssertEqual(resolved?.name, "Иван")
        XCTAssertNil(resolved?.avatarURL)
        XCTAssertEqual(fetches.count, 0)
    }

    func testFailedAvatarURLTriesOtherFallbacksWithoutFetchEmployee() async {
        let id = "fallback-\(UUID().uuidString)"
        let failed = URL(string: "https://demo.megaplan.ru/api/v3/user/\(id)/avatar/thumbnail?size=64x64")!
        await UserInfoCache.shared.cacheUserInfo(userId: id, name: "Иван", avatarURL: failed)
        let fetches = HitCounter()
        let probed = URLLog()
        installEmployeeCounter(fetches, id: id)
        await configureResolver(token: "secret")
        await UserInfoResolver.shared.setImageProbe { url, _ in
            probed.append(url.absoluteString)
            return url.path == "/api/v3/user/\(id)/avatar"
        }

        let replacement = await UserInfoResolver.shared.replacementAvatar(id: id, failedURL: failed)
        let resolved = await UserInfoResolver.shared.resolve(id: id)
        let stored = await UserInfoCache.shared.getUserInfo(for: id)

        XCTAssertEqual(replacement?.path, "/api/v3/user/\(id)/avatar")
        XCTAssertFalse(probed.snapshot.contains(failed.absoluteString))
        XCTAssertEqual(resolved?.name, "Иван")
        XCTAssertEqual(resolved?.avatarURL?.path, "/api/v3/user/\(id)/avatar")
        XCTAssertEqual(stored?.name, "Иван")
        XCTAssertEqual(fetches.count, 0)
    }

    private func configureResolver(token: String) async {
        await UserInfoResolver.shared.configure(
            api: MegaplanAPI(domain: "demo.megaplan.ru", token: token, session: session),
            tokenProvider: { token },
            domainProvider: { "demo.megaplan.ru" }
        )
    }

    private func installEmployeeCounter(_ fetches: HitCounter, id: String) {
        URLProtocolMock.handler = { request in
            if request.url?.path == "/api/v3/employee/\(id)" {
                fetches.increment()
            }
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://demo.megaplan.ru/")!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
    }
}

private final class HitCounter: @unchecked Sendable {
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

private final class URLLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    func append(_ value: String) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    var snapshot: [String] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}
