import Foundation

actor UserInfoCache {
    static let shared = UserInfoCache()
    
    private var cache: [String: CachedUserInfo] = [:]
    private let cacheExpiration: TimeInterval = 3600 // 1 hour
    
    struct CachedUserInfo {
        let name: String?
        let avatarURL: URL?
        let cachedAt: Date
    }
    
    private init() {}
    
    func getUserInfo(for userId: String) -> CachedUserInfo? {
        guard let cached = cache[userId] else { return nil }
        
        // Check if cache is still valid
        if Date().timeIntervalSince(cached.cachedAt) > cacheExpiration {
            cache.removeValue(forKey: userId)
            return nil
        }
        
        return cached
    }
    
    func cacheUserInfo(userId: String, name: String?, avatarURL: URL?) {
        cache[userId] = CachedUserInfo(
            name: name,
            avatarURL: avatarURL,
            cachedAt: Date()
        )
    }
    
    func clearCache() {
        cache.removeAll()
    }
}




