import XCTest
@testable import MegaplanHepler

final class SettingsSearchIndexTests: XCTestCase {

    func testSearch_RefreshKeyword_ReturnsSync() {
        let results = SettingsSearchIndex.shared.search("refresh")
        XCTAssertTrue(results.contains(.sync), "'refresh' must match Sync section")
    }

    func testSearch_PasswordKeyword_ReturnsAccount() {
        let results = SettingsSearchIndex.shared.search("password")
        XCTAssertTrue(results.contains(.account))
    }

    func testSearch_RussianAvatar_ReturnsAccount() {
        let results = SettingsSearchIndex.shared.search("аватар")
        XCTAssertTrue(results.contains(.account))
    }

    func testSearch_EmptyQuery_ReturnsAllSections() {
        let results = SettingsSearchIndex.shared.search("")
        XCTAssertEqual(Set(results), Set(SettingsSection.allCases))
    }

    func testSearch_NoMatch_ReturnsEmpty() {
        let results = SettingsSearchIndex.shared.search("xyzzyplugh")
        XCTAssertTrue(results.isEmpty)
    }
}
