import Foundation

protocol TaskService {
    func fetchTasks(token: String,
                    currentUserId: String,
                    sortBy: TaskSortKey,
                    statusFilter: TaskStatusFilter,
                    limit: Int) async throws -> [MegaplanTask]

    func fetchCurrentUserId(token: String) async throws -> String

    /// Server-side full-text search across the authenticated user's tasks.
    /// Megaplan v3 honors a top-level `q` query field that searches the title
    /// and (empirically) comment bodies — wider than a `name contains` filter.
    func searchTasks(token: String,
                     currentUserId: String,
                     query: String,
                     limit: Int) async throws -> [MegaplanTask]

    /// Fetches a task plus all of its comments fully expanded (author, timestamp,
    /// content HTML, attachments). Used by the markdown export shortcut.
    func fetchTaskComments(token: String, taskId: String) async throws -> TaskCommentsBundle
}

/// Resolves the name + avatar of an arbitrary employee. Used to lazily backfill
/// task participants whose names/avatars are not present in the task list response.
protocol EmployeeService {
    func fetchEmployee(id: String, token: String) async throws -> (name: String?, avatarURL: URL?)
}
