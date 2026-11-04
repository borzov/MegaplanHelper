import XCTest
@testable import MegaplanHepler

@MainActor
final class SessionLockoutTests: XCTestCase {

    func testThreeFailuresLockSignIn() async {
        let api = ThrowingAuthAPI()
        let state = AppState(api: api, userDefaults: isolatedDefaults(), keychain: InMemoryKeychain())
        await state.signIn(domain: "demo.megaplan.ru", login: "a@b.co", password: "x")
        await state.signIn(domain: "demo.megaplan.ru", login: "a@b.co", password: "x")
        await state.signIn(domain: "demo.megaplan.ru", login: "a@b.co", password: "x")
        await state.signIn(domain: "demo.megaplan.ru", login: "a@b.co", password: "x")
        XCTAssertEqual(state.lastAuthError, .lockout)
        XCTAssertNotNil(state.lockoutState)
        XCTAssertEqual(api.authenticateCalls, 3)
    }
}

private func isolatedDefaults() -> UserDefaults {
    let suiteName = "test-\(UUID().uuidString)"
    let suite = UserDefaults(suiteName: suiteName)!
    suite.removePersistentDomain(forName: suiteName)
    return suite
}

private enum SessionLockoutTestError: Error {
    case authenticationFailed
}

final class ThrowingAuthAPI: AuthenticationService, NotificationService, TaskService, EmployeeService {
    private(set) var authenticateCalls = 0

    func authenticate(login: String, password: String) async throws -> String {
        authenticateCalls += 1
        throw SessionLockoutTestError.authenticationFailed
    }

    func validateToken(token: String) async throws -> (isValid: Bool, firstName: String?, unreadCount: Int?, possibleActions: [String]?) {
        (false, nil, 0, nil)
    }

    func fetchNotifications(token: String) async throws -> [MegaplanNotification] {
        []
    }

    func fetchUnreadCount(token: String) async throws -> Int {
        0
    }

    func markAsRead(id: String, token: String) async throws {}

    func fetchTasks(
        token: String,
        currentUserId: String,
        sortBy: TaskSortKey,
        statusFilter: TaskStatusFilter,
        limit: Int
    ) async throws -> [MegaplanTask] {
        []
    }

    func fetchCurrentUserId(token: String) async throws -> String {
        ""
    }

    func searchTasks(
        token: String,
        currentUserId: String,
        query: String,
        limit: Int
    ) async throws -> [MegaplanTask] {
        []
    }

    func fetchTaskComments(token: String, taskId: String) async throws -> TaskCommentsBundle {
        TaskCommentsBundle(taskName: "", humanNumber: nil, comments: [])
    }

    func fetchEmployee(id: String, token: String) async throws -> (name: String?, avatarURL: URL?) {
        ("", nil)
    }
}
