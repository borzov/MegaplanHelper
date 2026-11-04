import XCTest
@testable import MegaplanHepler

final class WorkspaceAddressTests: XCTestCase {
    func testAdminPagesUsePopoverPathsAndBareDomain() {
        XCTAssertEqual(WorkspaceAddress.page(.knowledge, domain: "demo.megaplan.ru")?.absoluteString, "https://demo.megaplan.ru/knowledge/")
        XCTAssertEqual(WorkspaceAddress.page(.deals, domain: "demo.megaplan.ru")?.absoluteString, "https://demo.megaplan.ru/deals/list/")
        XCTAssertEqual(WorkspaceAddress.page(.tasks, domain: "demo.megaplan.ru")?.absoluteString, "https://demo.megaplan.ru/task/")
    }

    func testAdminPagesAcceptFullURLHost() {
        let url = WorkspaceAddress.page(.deals, domain: "https://demo.megaplan.ru/ignored")
        XCTAssertEqual(url?.absoluteString, "https://demo.megaplan.ru/deals/list/")
    }

    func testTaskCardStaysOnExistingShape() {
        XCTAssertEqual(
            WorkspaceAddress.taskCard(id: "1001", domain: "demo.megaplan.ru")?.absoluteString,
            "https://demo.megaplan.ru/task/1001/card/"
        )
    }

    func testRelativeNotificationLinkJoinsHost() {
        let link = URL(string: "/task/5/card/")!
        let resolved = WorkspaceAddress.resolve(link: link, domain: "demo.megaplan.ru")
        XCTAssertEqual(resolved?.absoluteString, "https://demo.megaplan.ru/task/5/card/")
    }

    func testAbsoluteLinkIsUnchanged() {
        let link = URL(string: "https://other.example/a")!
        XCTAssertEqual(WorkspaceAddress.resolve(link: link, domain: "demo.megaplan.ru"), link)
    }

    func testDiagnosticTextIsTheAPILog() {
        XCTAssertEqual(WorkspaceAddress.diagnosticText(), APILogger.getLogContent())
    }
}
