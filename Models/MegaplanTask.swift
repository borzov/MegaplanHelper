import Foundation

// MARK: - Domain model

/// Domain representation of a Megaplan v3 Task entity used by the UI layer.
struct MegaplanTask: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let status: TaskStatus
    let responsible: TaskParticipant?
    let owner: TaskParticipant?
    let auditors: [TaskParticipant]
    let executors: [TaskParticipant]
    let timeCreated: Date
    let activity: Date?
    let lastCommentTimeCreated: Date?
    /// Total comments on the task thread (Megaplan field `commentsCount`).
    let totalCommentsCount: Int
    let unreadCommentsCount: Int
    let humanNumber: Int?

    /// Returns the timestamp matching the given sort key for grouping/labelling purposes.
    func timestamp(for key: TaskSortKey) -> Date {
        switch key {
        case .activity: return activity ?? timeCreated
        case .timeCreated: return timeCreated
        case .lastCommentTimeCreated: return lastCommentTimeCreated ?? activity ?? timeCreated
        }
    }

    /// Builds the browser URL for the task card on the configured Megaplan host.
    /// - Parameter host: domain or full URL string from `AppState.domain`.
    func webURL(host: String) -> URL? {
        guard !id.isEmpty else { return nil }
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
            ? trimmed
            : "https://\(trimmed)"
        let cleaned = normalized.hasSuffix("/") ? String(normalized.dropLast()) : normalized
        return URL(string: "\(cleaned)/task/\(id)/card/")
    }
}

// MARK: - Participant

struct TaskParticipant: Equatable, Hashable {
    let id: String
    let contentType: String  // "Employee", "ContractorHuman", "ContractorCompany", "Group"
    let name: String
    let avatarURL: URL?

    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let initials = parts.compactMap { $0.first.map(String.init) }.joined()
        return initials.uppercased()
    }
}

// MARK: - Status

/// All documented v3 Task statuses.
/// Reference: bums\\task\\task\\api\\v03\\Entity\\Task — see local SDK docs.
enum TaskStatus: String, CaseIterable, Codable, Equatable, Hashable {
    case created
    case assigned
    case accepted
    case done
    case completed
    case rejected
    case cancelled
    case expired
    case delayed
    case template
    case overdue

    /// Statuses that represent in-flight work the user normally cares about.
    var isActive: Bool {
        switch self {
        case .created, .assigned, .accepted, .delayed, .overdue:
            return true
        case .done, .completed, .rejected, .cancelled, .expired, .template:
            return false
        }
    }

    /// SF Symbols-style indicator color category for the status dot in the UI.
    var indicatorKind: TaskStatusIndicator {
        switch self {
        case .created, .assigned, .accepted, .delayed:
            return .active
        case .overdue, .expired:
            return .overdue
        case .done, .completed:
            return .done
        case .rejected, .cancelled:
            return .cancelled
        case .template:
            return .neutral
        }
    }

    /// Human-readable label used in filters / tooltips.
    var displayName: String {
        switch self {
        case .created: return String(localized: "tasks.status.created")
        case .assigned: return String(localized: "tasks.status.assigned")
        case .accepted: return String(localized: "tasks.status.accepted")
        case .done: return String(localized: "tasks.status.done")
        case .completed: return String(localized: "tasks.status.completed")
        case .rejected: return String(localized: "tasks.status.rejected")
        case .cancelled: return String(localized: "tasks.status.cancelled")
        case .expired: return String(localized: "tasks.status.expired")
        case .delayed: return String(localized: "tasks.status.delayed")
        case .template: return String(localized: "tasks.status.template")
        case .overdue: return String(localized: "tasks.status.overdue")
        }
    }

    /// Decodes any string value, falling back to `.created` for unknown inputs and logging a warning.
    static func parse(_ raw: String?) -> TaskStatus {
        guard let raw, !raw.isEmpty else { return .created }
        if let known = TaskStatus(rawValue: raw) {
            return known
        }
        AppLogger.warning("Unknown task status received from API: \(raw) — falling back to .created")
        return .created
    }
}

enum TaskStatusIndicator {
    case active
    case overdue
    case done
    case cancelled
    case neutral
}

// MARK: - Sort key

/// Sort fields surfaced in the UI. Raw value matches the Megaplan v3 SortField.fieldName.
enum TaskSortKey: String, CaseIterable, Codable {
    case activity
    case timeCreated
    case lastCommentTimeCreated

    var apiFieldName: String { rawValue }

    var displayName: String {
        switch self {
        case .activity: return String(localized: "tasks.sort.activity")
        case .timeCreated: return String(localized: "tasks.sort.created")
        case .lastCommentTimeCreated: return String(localized: "tasks.sort.lastComment")
        }
    }
}

// MARK: - Status filter

/// Server-side status filter applied via the `statuses` query parameter.
enum TaskStatusFilter: String, CaseIterable, Codable {
    case active
    case all

    /// Returns the list of Megaplan status strings to send, or `nil` to omit the parameter.
    var apiStatuses: [String]? {
        switch self {
        case .active:
            return TaskStatus.allCases.filter(\.isActive).map(\.rawValue)
        case .all:
            return nil
        }
    }

    var displayName: String {
        switch self {
        case .active: return String(localized: "tasks.filter.active")
        case .all: return String(localized: "tasks.filter.all")
        }
    }
}
