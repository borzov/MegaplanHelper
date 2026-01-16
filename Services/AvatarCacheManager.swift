import Foundation
import AppKit

final class AvatarCacheManager {
    static let shared = AvatarCacheManager()
    
    private let cacheDirectory: URL
    private let cacheExpirationInterval: TimeInterval = 3600 // 1 час
    private let fileManager = FileManager.default
    
    private init() {
        let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        cacheDirectory = cachesURL.appendingPathComponent("MegaplanMenuBarApp", isDirectory: true)
            .appendingPathComponent("Avatars", isDirectory: true)

        // Create cache directory if needed
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)
    }
    
    func getCachedImage(for userId: String, from url: URL) async -> NSImage? {
        let cacheURL = cacheFileURL(for: userId)
        let metadataURL = metadataFileURL(for: userId)
        
        // Проверяем, существует ли файл и его метаданные
        guard fileManager.fileExists(atPath: cacheURL.path),
              let metadata = loadMetadata(from: metadataURL) else {
            return nil
        }
        
        // Проверяем, не истек ли срок кеша
        let now = Date()
        if now.timeIntervalSince(metadata.cachedAt) > cacheExpirationInterval {
            // Удаляем устаревший файл
            try? fileManager.removeItem(at: cacheURL)
            try? fileManager.removeItem(at: metadataURL)
            return nil
        }
        
        // Проверяем, изменился ли URL
        if metadata.originalURL != url.absoluteString {
            // URL изменился, удаляем старый кеш
            try? fileManager.removeItem(at: cacheURL)
            try? fileManager.removeItem(at: metadataURL)
            return nil
        }
        
        // Загружаем изображение из кеша
        guard let imageData = try? Data(contentsOf: cacheURL),
              let image = NSImage(data: imageData) else {
            return nil
        }
        
        return image
    }
    
    func cacheImage(_ image: NSImage, for userId: String, from url: URL) async {
        let cacheURL = cacheFileURL(for: userId)
        let metadataURL = metadataFileURL(for: userId)
        
        // Сохраняем изображение
        guard let tiffData = image.tiffRepresentation,
              let pngData = NSBitmapImageRep(data: tiffData)?.representation(using: .png, properties: [:]) else {
            return
        }
        
        try? pngData.write(to: cacheURL)
        
        // Сохраняем метаданные
        let metadata = CacheMetadata(
            cachedAt: Date(),
            originalURL: url.absoluteString
        )
        saveMetadata(metadata, to: metadataURL)
    }
    
    func loadImage(from url: URL, for userId: String) async -> NSImage? {
        // Check cache first
        if let cachedImage = await getCachedImage(for: userId, from: url) {
            return cachedImage
        }
        
        // Load from network
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            // Validate response
            guard let httpResponse = response as? HTTPURLResponse else {
                AppLogger.error("Invalid response type for avatar URL: \(url.absoluteString)")
                return nil
            }
            
            guard httpResponse.statusCode == 200 else {
                AppLogger.error("Avatar load failed with status \(httpResponse.statusCode) for URL: \(url.absoluteString)")
                return nil
            }
            
            // Create image
            guard let image = NSImage(data: data) else {
                AppLogger.error("Failed to create NSImage from data for URL: \(url.absoluteString)")
                return nil
            }
            
            // Cache the image
            await cacheImage(image, for: userId, from: url)
            
            AppLogger.debug("Successfully loaded and cached avatar for user \(userId)")
            return image
            
        } catch let error as URLError {
            switch error.code {
            case .cancelled:
                AppLogger.debug("Avatar loading cancelled for user \(userId)")
            case .notConnectedToInternet, .networkConnectionLost:
                AppLogger.error("No internet connection while loading avatar for user \(userId)")
            case .timedOut:
                AppLogger.error("Timeout while loading avatar for user \(userId)")
            default:
                AppLogger.error("Network error loading avatar for user \(userId): \(error.localizedDescription)")
            }
            return nil
            
        } catch {
            AppLogger.error("Unexpected error loading avatar for user \(userId): \(error.localizedDescription)")
            return nil
        }
    }
    
    private func cacheFileURL(for userId: String) -> URL {
        cacheDirectory.appendingPathComponent("\(userId).png")
    }
    
    private func metadataFileURL(for userId: String) -> URL {
        cacheDirectory.appendingPathComponent("\(userId).metadata.json")
    }
    
    private func loadMetadata(from url: URL) -> CacheMetadata? {
        guard let data = try? Data(contentsOf: url),
              let metadata = try? JSONDecoder().decode(CacheMetadata.self, from: data) else {
            return nil
        }
        return metadata
    }
    
    private func saveMetadata(_ metadata: CacheMetadata, to url: URL) {
        guard let data = try? JSONEncoder().encode(metadata) else {
            return
        }
        try? data.write(to: url)
    }
    
    func clearCache() {
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)
    }
}

private struct CacheMetadata: Codable {
    let cachedAt: Date
    let originalURL: String
}

