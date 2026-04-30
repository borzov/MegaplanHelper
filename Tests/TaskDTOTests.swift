import XCTest
@testable import MegaplanHepler

/// Tests TaskListEnvelope/TaskDTO decoding against the documented Megaplan v3 schema.
final class TaskDTOTests: XCTestCase {

    // MARK: - Helpers

    private func loadFixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            ?? URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Fixtures/\(name).json")
        return try Data(contentsOf: url)
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    // MARK: - Envelope shape

    func testDecodesAllTasksFromFixture() throws {
        let data = try loadFixture("tasks_response")
        let envelope = try decoder().decode(TaskListEnvelope.self, from: data)
        XCTAssertEqual(envelope.items.count, 3)
    }

    func testFirstTaskFieldsAreParsedCorrectly() throws {
        let data = try loadFixture("tasks_response")
        let envelope = try decoder().decode(TaskListEnvelope.self, from: data)
        let first = try XCTUnwrap(envelope.items.first)

        XCTAssertEqual(first.id, "1001")
        XCTAssertEqual(first.name, "Аналитика Q2 — подготовить отчёт")
        XCTAssertEqual(first.status, .assigned)
        XCTAssertEqual(first.humanNumber, 1001)
        XCTAssertEqual(first.totalCommentsCount, 10)
        XCTAssertEqual(first.unreadCommentsCount, 3)
        XCTAssertEqual(first.responsible?.id, "123")
        XCTAssertEqual(first.responsible?.name, "Иванова Анна")
        XCTAssertEqual(first.responsible?.avatarURL?.absoluteString,
                       "https://demo.megaplan.ru/img/avatar/123.png")
        XCTAssertEqual(first.owner?.id, "456")
        XCTAssertEqual(first.auditors.count, 1)
        XCTAssertEqual(first.auditors.first?.id, "789")
        XCTAssertNotNil(first.activity)
        XCTAssertNotNil(first.lastCommentTimeCreated)
    }

    func testTaskWithoutLastCommentParsesNil() throws {
        let data = try loadFixture("tasks_response")
        let envelope = try decoder().decode(TaskListEnvelope.self, from: data)
        let second = envelope.items[1]

        XCTAssertEqual(second.id, "1002")
        XCTAssertEqual(second.totalCommentsCount, 6)
        XCTAssertNil(second.lastCommentTimeCreated)
        XCTAssertNotNil(second.activity)  // present
    }

    func testTaskWithoutOptionalsHasReasonableDefaults() throws {
        let data = try loadFixture("tasks_response")
        let envelope = try decoder().decode(TaskListEnvelope.self, from: data)
        let third = envelope.items[2]

        XCTAssertEqual(third.id, "1003")
        XCTAssertEqual(third.totalCommentsCount, 4)
        XCTAssertNil(third.activity)
        XCTAssertNil(third.lastCommentTimeCreated)
        XCTAssertNil(third.owner)
        XCTAssertEqual(third.status, .overdue)
    }

    // MARK: - Status fallback

    func testUnknownStatusFallsBackToCreated() {
        XCTAssertEqual(TaskStatus.parse("unknown_status_string"), .created)
    }

    func testKnownStatusParsesCorrectly() {
        XCTAssertEqual(TaskStatus.parse("overdue"), .overdue)
        XCTAssertEqual(TaskStatus.parse("completed"), .completed)
        XCTAssertEqual(TaskStatus.parse("assigned"), .assigned)
    }

    func testNilStatusDefaultsToCreated() {
        XCTAssertEqual(TaskStatus.parse(nil), .created)
        XCTAssertEqual(TaskStatus.parse(""), .created)
    }
}
