import XCTest
@testable import MegaplanHepler

/// Sanity checks for `Pluralization.russian(...)` and `Pluralization.commentsLabel(_:)`.
///
/// NOTE: as of 2026-04, the project doesn't expose an Xcode test target, so this
/// file is currently kept alongside the other tests and verified manually
/// (or via `swift test` once a test target exists). Keep the cases here as a
/// living spec for the russian plural rule: one / few / many.
final class PluralizationTests: XCTestCase {
    func testRussianFormSelection() {
        // Sanity: assert the form chosen by the algorithm matches the CLDR ru rule.
        // We exercise representative values around the boundary cases
        // (mod 100 == 11..14 → many, mod 10 == 1 → one, mod 10 == 2..4 → few).
        let cases: [(Int, String)] = [
            (0, "many"),
            (1, "one"),
            (2, "few"),
            (3, "few"),
            (4, "few"),
            (5, "many"),
            (10, "many"),
            (11, "many"),
            (12, "many"),
            (14, "many"),
            (15, "many"),
            (21, "one"),
            (22, "few"),
            (24, "few"),
            (25, "many"),
            (101, "one"),
            (111, "many"),
            (121, "one")
        ]

        for (count, expected) in cases {
            let result = Pluralization.russian(count: count, one: "ONE", few: "FEW", many: "MANY")
            switch expected {
            case "one": XCTAssertEqual(result, "ONE", "count=\(count)")
            case "few": XCTAssertEqual(result, "FEW", "count=\(count)")
            case "many": XCTAssertEqual(result, "MANY", "count=\(count)")
            default: XCTFail("unknown expected \(expected)")
            }
        }
    }

    func testFormatPlaceholderIsSubstituted() {
        let value = Pluralization.russian(count: 7, one: "%d одно", few: "%d мало", many: "%d много")
        XCTAssertEqual(value, "7 много")
    }
}
