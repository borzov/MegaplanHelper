import XCTest
@testable import MegaplanHepler

final class MegaplanAPISessionTests: XCTestCase {
    override func tearDown() {
        URLProtocolMock.handler = nil
        super.tearDown()
    }

    func testUnreadCountUsesInjectedSessionAndBearerToken() async throws {
        URLProtocolMock.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
            XCTAssertTrue(request.url?.path.hasSuffix("/api/v3/notification/counter") == true)
            let body = Data("{\"data\":{\"count\":7}}".utf8)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }

        let api = MegaplanAPI(domain: "demo.megaplan.ru", token: "token-1", session: URLProtocolMock.makeSession())
        let count = try await api.fetchUnreadCount()
        XCTAssertEqual(count, 7)
    }

    func testMarkAsReadSendsDeleteWithStoredBearer() async throws {
        URLProtocolMock.handler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
            XCTAssertTrue(request.url?.path.hasSuffix("/api/v3/notification/n1") == true)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let api = MegaplanAPI(domain: "demo.megaplan.ru", token: "token-1", session: URLProtocolMock.makeSession())
        try await api.markAsRead(id: "n1")
    }
}
