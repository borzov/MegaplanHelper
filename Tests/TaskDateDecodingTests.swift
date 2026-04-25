import XCTest
@testable import MegaplanHepler

final class TaskDateDecodingTests: XCTestCase {

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    // MARK: - DateTime envelope

    func testDecodesDateTimeWithTimezoneOffset() throws {
        let json = #"{"contentType":"DateTime","value":"2026-04-10T10:30:00+03:00"}"#
        let data = Data(json.utf8)
        let parsed = try decoder.decode(MegaplanDateTime.self, from: data)

        // 10:30 +03:00 == 07:30 UTC
        var components = DateComponents()
        components.year = 2026
        components.month = 4
        components.day = 10
        components.hour = 7
        components.minute = 30
        components.second = 0
        components.timeZone = TimeZone(secondsFromGMT: 0)
        let expected = Calendar(identifier: .gregorian).date(from: components)
        XCTAssertEqual(parsed.value, expected)
    }

    func testDecodesDateTimeWithFractionalSeconds() throws {
        let json = #"{"contentType":"DateTime","value":"2026-04-10T10:30:00.123Z"}"#
        let data = Data(json.utf8)
        let parsed = try decoder.decode(MegaplanDateTime.self, from: data)
        XCTAssertNotNil(parsed.value)
    }

    func testThrowsOnInvalidDateTimeValue() {
        let json = #"{"contentType":"DateTime","value":"not-a-date"}"#
        let data = Data(json.utf8)
        XCTAssertThrowsError(try decoder.decode(MegaplanDateTime.self, from: data))
    }

    // MARK: - DateOnly envelope

    func testDecodesDateOnlyEnvelope() throws {
        let json = #"{"contentType":"DateOnly","year":2026,"month":4,"day":20}"#
        let data = Data(json.utf8)
        let parsed = try decoder.decode(MegaplanDateOnly.self, from: data)

        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: parsed.value)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 4)
        XCTAssertEqual(components.day, 20)
    }
}
