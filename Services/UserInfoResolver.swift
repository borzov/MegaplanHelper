import Foundation

/// Single entry point for "give me name + avatar for user id X".
///
/// Strategy:
/// 1. Hit `UserInfoCache.shared` when the row already has both name and avatar.
/// 2. On a gap, call `EmployeeService.fetchEmployee(id:)` and, if the avatar is
///    still missing, probe `ParticipantDirectory.fallbackAvatarPaths`.
/// 3. De-duplicates concurrent requests for the same id so a screenful of rows
///    asking about the same user produces one network round-trip.
///
/// Notification fetch and task parsing must write through `remember(seeds:)` only.
actor UserInfoResolver {
    static let shared = UserInfoResolver()

    private var api: EmployeeService?
    private var tokenProvider: (@Sendable () async -> String?)?
    private var domainProvider: (@Sendable () async -> String)?
    private var inflight: [String: Task<(name: String?, avatarURL: URL?)?, Never>] = [:]
    /// Ids we already tried to fill. Cleared on logout and when the cache row expires.
    private var avatarMisses: Set<String> = []

    func configure(
        api: EmployeeService,
        tokenProvider: @escaping @Sendable () async -> String?,
        domainProvider: (@Sendable () async -> String)? = nil
    ) {
        self.api = api
        self.tokenProvider = tokenProvider
        self.domainProvider = domainProvider
    }

    func clearAvatarMisses() {
        avatarMisses.removeAll()
    }

    /// Merges seeds into the cache. An incoming nil does not wipe a known name or avatar.
    /// An empty seed (no name and no avatar) records a negative row only when nothing is stored yet.
    func remember(seeds: [ParticipantSeed]) async {
        for seed in seeds where !seed.id.isEmpty {
            let incomingName = Self.normalized(seed.name)
            let existing = await UserInfoCache.shared.getUserInfo(for: seed.id)
            if incomingName == nil, seed.avatarURL == nil {
                if existing == nil {
                    await UserInfoCache.shared.cacheUserInfo(userId: seed.id, name: nil, avatarURL: nil)
                }
                continue
            }

            let name = incomingName ?? existing?.name
            let avatarURL = seed.avatarURL ?? existing?.avatarURL
            if let existing, existing.name == name, existing.avatarURL == avatarURL {
                continue
            }
            await UserInfoCache.shared.cacheUserInfo(userId: seed.id, name: name, avatarURL: avatarURL)
            if Self.normalized(name) != nil, avatarURL != nil {
                avatarMisses.remove(seed.id)
            }
        }
    }

    /// Returns whatever's known about the user (cache hit or remote fetch).
    /// Returns `nil` if neither source can produce data.
    func resolve(id: String) async -> (name: String?, avatarURL: URL?)? {
        guard !id.isEmpty else { return nil }

        switch await decide(id: id) {
        case .ready(let answer):
            return answer
        case .lookup:
            break
        }

        if let existing = inflight[id] {
            return await existing.value
        }

        let api = self.api
        let tokenProvider = self.tokenProvider
        let domainProvider = self.domainProvider
        let task = Task<(name: String?, avatarURL: URL?)?, Never> {
            await UserInfoResolver.shared.lookup(
                id: id,
                api: api,
                tokenProvider: tokenProvider,
                domainProvider: domainProvider
            )
        }
        inflight[id] = task
        let result = await task.value
        inflight[id] = nil
        return result
    }

    private enum CacheDecision {
        case ready((name: String?, avatarURL: URL?)?)
        case lookup
    }

    private func decide(id: String) async -> CacheDecision {
        if avatarMisses.contains(id) {
            if let cached = await UserInfoCache.shared.getUserInfo(for: id) {
                return .ready((cached.name, cached.avatarURL))
            }
            avatarMisses.remove(id)
        }

        if let cached = await UserInfoCache.shared.getUserInfo(for: id) {
            let hasName = Self.normalized(cached.name) != nil
            if hasName, cached.avatarURL != nil {
                return .ready((cached.name, cached.avatarURL))
            }
        }
        return .lookup
    }

    private func lookup(
        id: String,
        api: EmployeeService?,
        tokenProvider: (@Sendable () async -> String?)?,
        domainProvider: (@Sendable () async -> String)?
    ) async -> (name: String?, avatarURL: URL?)? {
        if case .ready(let answer) = await decide(id: id) {
            return answer
        }

        let cached = await UserInfoCache.shared.getUserInfo(for: id)
        var name = cached?.name
        var avatar = cached?.avatarURL
        var employeeAnswered = false

        if let api, let tokenProvider {
            let token = await tokenProvider()
            if let token, !token.isEmpty {
                do {
                    let result = try await api.fetchEmployee(id: id, token: token)
                    if let fetched = Self.normalized(result.name) {
                        name = fetched
                    }
                    if let fetched = result.avatarURL {
                        avatar = fetched
                    }
                    employeeAnswered = true
                } catch {
                    AppLogger.warning("UserInfoResolver: fetchEmployee(\(id)) failed: \(error.localizedDescription)")
                }
            }
        }

        let domain: String
        if let domainProvider {
            domain = await domainProvider()
        } else {
            domain = ""
        }
        var triedFallbacks = false
        if avatar == nil, !domain.isEmpty {
            triedFallbacks = true
            avatar = await firstWorkingFallbackAvatar(userId: id, domain: domain)
        }

        await remember(seeds: [ParticipantSeed(id: id, name: name, avatarURL: avatar)])
        let stored = await UserInfoCache.shared.getUserInfo(for: id)
        let resolvedName = stored?.name ?? name
        let resolvedAvatar = stored?.avatarURL ?? avatar
        let hasName = Self.normalized(resolvedName) != nil

        if hasName, resolvedAvatar != nil {
            avatarMisses.remove(id)
        } else if triedFallbacks || (employeeAnswered && !domain.isEmpty) {
            avatarMisses.insert(id)
        }

        if !hasName, resolvedAvatar == nil, stored == nil {
            return nil
        }
        return (resolvedName, resolvedAvatar)
    }

    private func firstWorkingFallbackAvatar(userId: String, domain: String) async -> URL? {
        for url in Self.absoluteFallbackAvatarURLs(userId: userId, domain: domain) {
            if await AvatarCacheManager.shared.loadImage(from: url, for: userId) != nil {
                return url
            }
        }
        return nil
    }

    /// `WorkspaceAddress.resolve` keeps the path and drops the query, so `size=64x64`
    /// is appended after the host is known.
    private static func absoluteFallbackAvatarURLs(userId: String, domain: String) -> [URL] {
        guard let root = URL(string: "/"),
              let base = WorkspaceAddress.resolve(link: root, domain: domain) else {
            return []
        }
        return ParticipantDirectory.fallbackAvatarPaths(userId: userId).compactMap { relative in
            let relativeString: String
            if let query = relative.query, !query.isEmpty {
                relativeString = "\(relative.path)?\(query)"
            } else {
                relativeString = relative.path
            }
            return URL(string: relativeString, relativeTo: base)?.absoluteURL
        }
    }

    private static func normalized(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
