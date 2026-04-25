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

    func testSearch_SingleCharacterToken_DegeneratesToNoOp() {
        // Single-char tokens are filtered before substring matching;
        // when nothing remains, search returns all sections (search-as-you-type).
        let results = SettingsSearchIndex.shared.search("о")
        XCTAssertEqual(Set(results), Set(SettingsSection.allCases),
                       "Single-character tokens must be ignored, not flood results via substring match")
    }

    func testSearch_MixedShortAndValidTokens_FiltersShortOnly() {
        // The actual I-1 regression: short token "о" must not flood when paired with a real query.
        let results = SettingsSearchIndex.shared.search("о password")
        XCTAssertEqual(Set(results), Set([.account]),
                       "'о' is filtered out; only 'password' contributes — Account only")
    }

    func testSearch_MultiToken_UnionOfMatches() {
        let results = SettingsSearchIndex.shared.search("password reset")
        XCTAssertTrue(results.contains(.account), "'password' must match Account")
        XCTAssertTrue(results.contains(.storage), "'reset' must match Storage")
    }

    func testSearch_UpperCaseQuery_StillMatches() {
        let results = SettingsSearchIndex.shared.search("REFRESH")
        XCTAssertTrue(results.contains(.sync), "Upper-case query must match thanks to lowercased() normalisation")
    }

    func testSearch_WhitespaceOnlyQuery_ReturnsAllSections() {
        let results = SettingsSearchIndex.shared.search("   ")
        XCTAssertEqual(Set(results), Set(SettingsSection.allCases))
    }
}
