import Foundation

protocol TaskService {
    func fetchTasks(token: String,
                    currentUserId: String,
                    sortBy: TaskSortKey,
                    statusFilter: TaskStatusFilter,
                    limit: Int) async throws -> [MegaplanTask]

    func fetchCurrentUserId(token: String) async throws -> String
}

/// Resolves the name + avatar of an arbitrary employee. Used to lazily backfill
/// task participants whose names/avatars are not present in the task list response.
protocol EmployeeService {
    func fetchEmployee(id: String, token: String) async throws -> (name: String?, avatarURL: URL?)
}
