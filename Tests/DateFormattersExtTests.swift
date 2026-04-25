import XCTest
@testable import MegaplanHepler

final class DateFormattersExtTests: XCTestCase {

    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 25, hour: 12))!

    func testRelative_8DaysAgo_ReturnsLastWeek() {
        let date = now.addingTimeInterval(-8 * 86400)
        let result = DateFormatters.relative(date, now: now)
        XCTAssertEqual(result, "на прошлой неделе")
    }

    func testRelative_15DaysAgo_ReturnsTwoWeeksAgo() {
        let date = now.addingTimeInterval(-15 * 86400)
        let result = DateFormatters.relative(date, now: now)
        XCTAssertEqual(result, "2 нед. назад")
    }

    func testRelative_45DaysAgo_ReturnsMonthsAgo() {
        let date = now.addingTimeInterval(-45 * 86400)
        let result = DateFormatters.relative(date, now: now)
        XCTAssertTrue(result.contains("мес"), "Expected months-ago format, got \(result)")
    }

    func testRelative_400DaysAgo_FallsBackToDayMonthYear() {
        let date = now.addingTimeInterval(-400 * 86400)
        let result = DateFormatters.relative(date, now: now)
        XCTAssertTrue(result.contains("2025"), "Expected year fallback, got \(result)")
    }
}
