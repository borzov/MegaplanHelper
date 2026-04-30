import XCTest
@testable import MegaplanHepler

final class TaskSortingTests: XCTestCase {

    private func makeTask(id: String,
                          activity: Date? = nil,
                          created: Date,
                          lastComment: Date? = nil,
                          status: TaskStatus = .assigned) -> MegaplanTask {
        MegaplanTask(
            id: id,
            name: "Task \(id)",
            status: status,
            responsible: nil,
            owner: nil,
            auditors: [],
            executors: [],
            timeCreated: created,
            activity: activity,
            lastCommentTimeCreated: lastComment,
            totalCommentsCount: 0,
            unreadCommentsCount: 0,
            humanNumber: nil
        )
    }

    func testSortKeyApiFieldNamesMatchMegaplanContract() {
        XCTAssertEqual(TaskSortKey.activity.apiFieldName, "activity")
        XCTAssertEqual(TaskSortKey.timeCreated.apiFieldName, "timeCreated")
        XCTAssertEqual(TaskSortKey.lastCommentTimeCreated.apiFieldName, "lastCommentTimeCreated")
    }

    func testTaskTimestampForActivityKey() {
        let now = Date()
        let earlier = now.addingTimeInterval(-3600)
        let task = makeTask(id: "1", activity: now, created: earlier)
        XCTAssertEqual(task.timestamp(for: .activity), now)
    }

    func testTaskTimestampForActivityKeyFallsBackToCreatedWhenAbsent() {
        let earlier = Date().addingTimeInterval(-3600)
        let task = makeTask(id: "1", activity: nil, created: earlier)
        XCTAssertEqual(task.timestamp(for: .activity), earlier)
    }

    func testTaskTimestampForLastCommentFallsBackThroughActivity() {
        let now = Date()
        let earlier = now.addingTimeInterval(-3600)
        let veryEarlier = now.addingTimeInterval(-7200)
        let task = makeTask(id: "1", activity: earlier, created: veryEarlier, lastComment: nil)
        XCTAssertEqual(task.timestamp(for: .lastCommentTimeCreated), earlier)
    }

    // MARK: - Status partitioning

    func testActiveStatusesIncludeExpectedSet() {
        let expected: Set<TaskStatus> = [.created, .assigned, .accepted, .delayed, .overdue]
        let actual = Set(TaskStatus.allCases.filter(\.isActive))
        XCTAssertEqual(actual, expected)
    }

    func testTerminalStatusesAreNotActive() {
        XCTAssertFalse(TaskStatus.completed.isActive)
        XCTAssertFalse(TaskStatus.done.isActive)
        XCTAssertFalse(TaskStatus.rejected.isActive)
        XCTAssertFalse(TaskStatus.cancelled.isActive)
        XCTAssertFalse(TaskStatus.expired.isActive)
        XCTAssertFalse(TaskStatus.template.isActive)
    }

    func testStatusFilterActiveProducesCorrectAPIList() {
        let statuses = TaskStatusFilter.active.apiStatuses
        XCTAssertNotNil(statuses)
        XCTAssertEqual(Set(statuses ?? []),
                       Set(["created", "assigned", "accepted", "delayed", "overdue"]))
    }

    func testStatusFilterAllOmitsParameter() {
        XCTAssertNil(TaskStatusFilter.all.apiStatuses)
    }
}
