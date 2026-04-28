import XCTest
@testable import MegaplanHepler

@MainActor
final class NotificationEventTypeFilterTests: XCTestCase {
    func testTypeFilterOptionsIncludeOnlyActiveTypesWithCounts() {
        let viewModel = makeViewModel()
        viewModel.notifications = [
            makeNotification(id: "1", type: "BumsTaskN_TaskAccepted", isRead: false),
            makeNotification(id: "2", type: "BumsTaskN_TaskAccepted", isRead: true),
            makeNotification(id: "3", type: "BumsTradeN_DealAddRole", isRead: false),
            makeNotification(id: "4", type: nil, isRead: false)
        ]

        viewModel.updateGroupedNotifications()

        XCTAssertEqual(viewModel.typeFilterOptions.count, 3)
        XCTAssertEqual(viewModel.typeFilterOptions.first?.typeKey, "BumsTaskN_TaskAccepted")
        XCTAssertEqual(viewModel.typeFilterOptions.first?.count, 2)

        let untyped = viewModel.typeFilterOptions.first(where: { $0.typeKey.isEmpty })
        XCTAssertEqual(untyped?.count, 1)
    }

    func testTypeFilterOptionsRespectShowOnlyUnread() {
        let viewModel = makeViewModel()
        viewModel.notifications = [
            makeNotification(id: "1", type: "BumsTaskN_TaskAccepted", isRead: false),
            makeNotification(id: "2", type: "BumsTradeN_DealAddRole", isRead: true)
        ]
        viewModel.showOnlyUnread = true

        viewModel.updateGroupedNotifications()

        XCTAssertEqual(viewModel.typeFilterOptions.count, 1)
        XCTAssertEqual(viewModel.typeFilterOptions.first?.typeKey, "BumsTaskN_TaskAccepted")
    }

    func testApplyingTypeFilterKeepsOnlyMatchingNotifications() {
        let viewModel = makeViewModel()
        viewModel.notifications = [
            makeNotification(id: "1", type: "BumsTaskN_TaskAccepted", isRead: false),
            makeNotification(id: "2", type: "BumsTradeN_DealAddRole", isRead: false)
        ]
        viewModel.selectedTypeFilterKeys = ["BumsTradeN_DealAddRole"]

        viewModel.updateGroupedNotifications()

        let ids = viewModel.groupedNotifications.flatMap(\.notifications).map(\.id)
        XCTAssertEqual(ids, ["2"])
    }

    func testMissingSelectedTypeResetsToAll() {
        let viewModel = makeViewModel()
        viewModel.notifications = [makeNotification(id: "1", type: "BumsTaskN_TaskAccepted", isRead: false)]
        viewModel.selectedTypeFilterKeys = ["BumsTradeN_DealAddRole"]

        viewModel.updateGroupedNotifications()

        XCTAssertTrue(viewModel.selectedTypeFilterKeys.isEmpty)
    }

    func testApplyingMultipleTypesKeepsNotificationsForEverySelectedType() {
        let viewModel = makeViewModel()
        viewModel.notifications = [
            makeNotification(id: "1", type: "BumsTaskN_TaskAccepted", isRead: false),
            makeNotification(id: "2", type: "BumsTradeN_DealAddRole", isRead: false),
            makeNotification(id: "3", type: "BumsItemN_ParticipantsAdded", isRead: false)
        ]
        viewModel.selectedTypeFilterKeys = ["BumsTaskN_TaskAccepted", "BumsTradeN_DealAddRole"]

        viewModel.updateGroupedNotifications()

        let ids = Set(viewModel.groupedNotifications.flatMap(\.notifications).map(\.id))
        XCTAssertEqual(ids, Set(["1", "2"]))
    }

    private func makeViewModel() -> NotificationListViewModel {
        let suite = UserDefaults(suiteName: UUID().uuidString)!
        return NotificationListViewModel(appState: AppState(userDefaults: suite), userDefaults: suite)
    }

    private func makeNotification(id: String, type: String?, isRead: Bool) -> MegaplanNotification {
        MegaplanNotification(
            id: id,
            title: "Title",
            body: "Body",
            createdAt: Date(),
            link: nil,
            isRead: isRead,
            type: type
        )
    }
}
