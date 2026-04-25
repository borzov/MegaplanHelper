import Foundation

/// Single entry point for "give me name + avatar for user id X".
///
/// Strategy:
/// 1. Hit `UserInfoCache.shared` first — populated by every notification + task fetch.
/// 2. On cache miss, lazily call `EmployeeService.fetchEmployee(id:)` and seed the cache.
/// 3. De-duplicates concurrent requests for the same id so a screenful of rows
///    asking about the same user produces one network round-trip.
actor UserInfoResolver {
    static let shared = UserInfoResolver()

    private var api: EmployeeService?
    private var tokenProvider: (@Sendable () async -> String?)?
    private var inflight: [String: Task<(name: String?, avatarURL: URL?)?, Never>] = [:]

    func configure(api: EmployeeService, tokenProvider: @escaping @Sendable () async -> String?) {
        self.api = api
        self.tokenProvider = tokenProvider
    }

    /// Returns whatever's known about the user (cache hit or remote fetch).
    /// Returns `nil` if neither source can produce data.
    func resolve(id: String) async -> (name: String?, avatarURL: URL?)? {
        guard !id.isEmpty else { return nil }

        if let cached = await UserInfoCache.shared.getUserInfo(for: id) {
            return (cached.name, cached.avatarURL)
        }

        if let existing = inflight[id] {
            return await existing.value
        }

        guard let api, let tokenProvider else { return nil }

        let task = Task<(name: String?, avatarURL: URL?)?, Never> { [api, tokenProvider] in
            guard let token = await tokenProvider() else { return nil }
            do {
                let result = try await api.fetchEmployee(id: id, token: token)
                if result.name != nil || result.avatarURL != nil {
                    await UserInfoCache.shared.cacheUserInfo(
                        userId: id,
                        name: result.name,
                        avatarURL: result.avatarURL
                    )
                }
                return result
            } catch {
                AppLogger.warning("UserInfoResolver: fetchEmployee(\(id)) failed: \(error.localizedDescription)")
                return nil
            }
        }
        inflight[id] = task
        let result = await task.value
        inflight[id] = nil
        return result
    }
}
