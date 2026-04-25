import Foundation

/// Builds Megaplan v3 `TaskFilter` JSON payloads for the `filter=` query parameter.
///
/// The list endpoint `GET /api/v3/task` accepts a JSON-encoded TaskFilter that wraps
/// a `FilterTermGroup` of `FilterTermRef` terms. To express "all tasks the current user
/// participates in" we OR-join four `FilterTermRef`s targeting `responsible`, `owner`,
/// `auditors`, and `executors`.
enum MegaplanTaskFilterBuilder {
    /// Builds the "my tasks" filter as a JSON-friendly dictionary tree.
    ///
    /// The Megaplan v3 server rejects `"OR"` joins in a single `FilterTermGroup`
    /// (only `"AND"` is allowed). To express "all tasks where I participate" without
    /// fanning out to 4 separate requests, we filter on the synthetic `participant`
    /// field that already aggregates responsible / owner / auditors / executors
    /// server-side.
    /// - Parameter currentUserId: the authenticated user's Employee id
    static func buildMyTasksFilter(currentUserId: String) -> [String: Any] {
        let userRef: [String: Any] = [
            "contentType": "Employee",
            "id": currentUserId
        ]

        let participantTerm: [String: Any] = [
            "contentType": "FilterTermRef",
            "field": "participant",
            "comparison": "equals",
            "value": [userRef]
        ]

        return [
            "contentType": "TaskFilter",
            "config": [
                "contentType": "FilterConfig",
                "termGroup": [
                    "contentType": "FilterTermGroup",
                    "join": "and",
                    "terms": [participantTerm]
                ]
            ]
        ]
    }

    /// Serializes a filter tree to a compact JSON string suitable for use as a query parameter.
    /// - Parameter filter: filter tree as returned by `buildMyTasksFilter`
    /// - Throws: `NetworkError.encodingFailed` (mapped from `JSONSerialization`) on failure
    static func serialize(_ filter: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: filter, options: [.sortedKeys])
        guard let string = String(data: data, encoding: .utf8) else {
            throw NetworkError.decodingFailed
        }
        return string
    }

    /// Builds a `[SortField]` JSON string for the `sortBy=` query parameter.
    /// - Parameters:
    ///   - key: sort field
    ///   - desc: descending order flag
    static func serializeSort(key: TaskSortKey, desc: Bool = true) throws -> String {
        let sortField: [String: Any] = [
            "contentType": "SortField",
            "fieldName": key.apiFieldName,
            "desc": desc
        ]
        let data = try JSONSerialization.data(withJSONObject: [sortField], options: [.sortedKeys])
        guard let string = String(data: data, encoding: .utf8) else {
            throw NetworkError.decodingFailed
        }
        return string
    }

    /// Builds a `[String]` JSON array for the `statuses=` query parameter.
    static func serializeStatuses(_ statuses: [String]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: statuses, options: [.sortedKeys])
        guard let string = String(data: data, encoding: .utf8) else {
            throw NetworkError.decodingFailed
        }
        return string
    }
}
