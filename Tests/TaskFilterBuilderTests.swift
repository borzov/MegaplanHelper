import XCTest
@testable import MegaplanHepler

final class TaskFilterBuilderTests: XCTestCase {

    func testBuildMyTasksFilterUsesParticipantField() {
        let filter = MegaplanTaskFilterBuilder.buildMyTasksFilter(currentUserId: "42")

        XCTAssertEqual(filter["contentType"] as? String, "TaskFilter")
        let config = try! XCTUnwrap(filter["config"] as? [String: Any])
        let group = try! XCTUnwrap(config["termGroup"] as? [String: Any])
        XCTAssertEqual(group["contentType"] as? String, "FilterTermGroup")
        XCTAssertEqual(group["join"] as? String, "and",
                       "Megaplan v3 only accepts 'and'/'or' lowercase for FilterTermGroup.join")
        let terms = try! XCTUnwrap(group["terms"] as? [[String: Any]])
        XCTAssertEqual(terms.count, 1, "Single 'participant' term covers all user roles")

        let term = terms[0]
        XCTAssertEqual(term["contentType"] as? String, "FilterTermRef")
        XCTAssertEqual(term["field"] as? String, "participant")
        XCTAssertEqual(term["comparison"] as? String, "equals")
        let value = try! XCTUnwrap(term["value"] as? [[String: Any]])
        XCTAssertEqual(value.count, 1)
        XCTAssertEqual(value[0]["contentType"] as? String, "Employee")
        XCTAssertEqual(value[0]["id"] as? String, "42")
    }

    func testSerializeProducesValidJSON() throws {
        let filter = MegaplanTaskFilterBuilder.buildMyTasksFilter(currentUserId: "99")
        let json = try MegaplanTaskFilterBuilder.serialize(filter)

        // Round-trip through JSONSerialization to confirm the string is valid JSON.
        let data = try XCTUnwrap(json.data(using: .utf8))
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?["contentType"] as? String, "TaskFilter")
    }

    func testSerializeSortBuildsExpectedJSON() throws {
        let json = try MegaplanTaskFilterBuilder.serializeSort(key: .activity, desc: true)
        let data = try XCTUnwrap(json.data(using: .utf8))
        let parsed = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        let entry = try XCTUnwrap(parsed?.first)
        XCTAssertEqual(entry["contentType"] as? String, "SortField")
        XCTAssertEqual(entry["fieldName"] as? String, "activity")
        XCTAssertEqual(entry["desc"] as? Bool, true)
    }

    func testSerializeStatusesProducesArray() throws {
        let json = try MegaplanTaskFilterBuilder.serializeStatuses(["created", "assigned"])
        let data = try XCTUnwrap(json.data(using: .utf8))
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String]
        XCTAssertEqual(parsed, ["assigned", "created"])  // sortedKeys
    }
}
