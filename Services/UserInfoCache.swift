import Foundation

actor UserInfoCache {
    static let shared = UserInfoCache()

    private var cache: [String: CachedUserInfo] = [:]
    private var accessOrder: [String] = [] // Track access order for LRU
    private let cacheExpiration: TimeInterval = 3600 // 1 hour
    private let maxCacheSize: Int = 500 // Maximum number of entries

    struct CachedUserInfo {
        let name: String?
        let avatarURL: URL?
        let cachedAt: Date
        var lastAccessedAt: Date
    }

    private init() {}

    func getUserInfo(for userId: String) -> CachedUserInfo? {
        guard var cached = cache[userId] else { return nil }

        // Check if cache is still valid
        if Date().timeIntervalSince(cached.cachedAt) > cacheExpiration {
            cache.removeValue(forKey: userId)
            removeFromAccessOrder(userId)
            return nil
        }

        // Update last accessed time and move to end of access order (most recent)
        cached.lastAccessedAt = Date()
        cache[userId] = cached
        updateAccessOrder(for: userId)

        return cached
    }

    func cacheUserInfo(userId: String, name: String?, avatarURL: URL?) {
        // Check if this is an update to existing entry
        let isNewEntry = cache[userId] == nil

        // Evict least recently used entries if cache is full and this is a new entry
        if isNewEntry {
            while cache.count >= maxCacheSize {
                evictLRU()
            }
        }

        cache[userId] = CachedUserInfo(
            name: name,
            avatarURL: avatarURL,
            cachedAt: Date(),
            lastAccessedAt: Date()
        )
        updateAccessOrder(for: userId)
    }

    func clearCache() {
        cache.removeAll()
        accessOrder.removeAll()
    }

    // MARK: - Private LRU Helpers

    private func updateAccessOrder(for userId: String) {
        // Remove if exists and append to end (most recent)
        removeFromAccessOrder(userId)
        accessOrder.append(userId)
    }

    private func removeFromAccessOrder(_ userId: String) {
        if let index = accessOrder.firstIndex(of: userId) {
            accessOrder.remove(at: index)
        }
    }

    private func evictLRU() {
        // Remove least recently used (first in access order)
        guard let leastRecent = accessOrder.first else { return }
        cache.removeValue(forKey: leastRecent)
        accessOrder.removeFirst()
        AppLogger.debug("Evicted LRU cache entry: \(leastRecent)")
    }
}








