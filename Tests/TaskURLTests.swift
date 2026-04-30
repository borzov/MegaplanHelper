import XCTest
@testable import MegaplanHepler

final class TaskURLTests: XCTestCase {

    private func makeTask(id: String) -> MegaplanTask {
        MegaplanTask(
            id: id,
            name: "Test",
            status: .assigned,
            responsible: nil,
            owner: nil,
            auditors: [],
            executors: [],
            timeCreated: Date(),
            activity: nil,
            lastCommentTimeCreated: nil,
            totalCommentsCount: 0,
            unreadCommentsCount: 0,
            humanNumber: nil
        )
    }

    func testWebURLBuildsHTTPSFromBareDomain() {
        let url = makeTask(id: "1001").webURL(host: "demo.megaplan.ru")
        XCTAssertEqual(url?.absoluteString, "https://demo.megaplan.ru/task/1001/card/")
    }

    func testWebURLPreservesExplicitScheme() {
        let url = makeTask(id: "42").webURL(host: "https://demo.megaplan.ru")
        XCTAssertEqual(url?.absoluteString, "https://demo.megaplan.ru/task/42/card/")
    }

    func testWebURLDropsTrailingSlashFromHost() {
        let url = makeTask(id: "7").webURL(host: "https://demo.megaplan.ru/")
        XCTAssertEqual(url?.absoluteString, "https://demo.megaplan.ru/task/7/card/")
    }

    func testWebURLAcceptsHTTPSchemeUnchanged() {
        let url = makeTask(id: "9").webURL(host: "http://internal.megaplan.local")
        XCTAssertEqual(url?.absoluteString, "http://internal.megaplan.local/task/9/card/")
    }

    func testWebURLReturnsNilForEmptyId() {
        XCTAssertNil(makeTask(id: "").webURL(host: "demo.megaplan.ru"))
    }

    func testWebURLReturnsNilForEmptyHost() {
        XCTAssertNil(makeTask(id: "1").webURL(host: ""))
        XCTAssertNil(makeTask(id: "1").webURL(host: "   "))
    }
}
