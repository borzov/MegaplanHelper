import Foundation
import AppKit

/// Errors that can occur during avatar caching operations
enum AvatarCacheError: Error {
    case fileTooLarge(size: Int64)
    case invalidImageData
    case fileSystemError(Error)
}

final class AvatarCacheManager {
    static let shared = AvatarCacheManager()

    private let cacheDirectory: URL
    private let cacheExpirationInterval: TimeInterval = 3600 // 1 час
    private let fileManager = FileManager.default

    // Network session with configured timeouts
    private static let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10  // 10 seconds for request
        config.timeoutIntervalForResource = 30  // 30 seconds total
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    // Rate limiting: max 5 concurrent downloads
    private let downloadSemaphore = DispatchSemaphore(value: 5)

    // Size limits
    private static let maxAvatarSize: Int64 = 1024 * 1024  // 1MB

    private static let metadataDecoder = JSONDecoder()
    private static let metadataEncoder = JSONEncoder()

    private init() {
        let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        cacheDirectory = cachesURL.appendingPathComponent("MegaplanMenuBarApp", isDirectory: true)
            .appendingPathComponent("Avatars", isDirectory: true)

        createCacheDirectoryIfNeeded()
    }

    /// Creates cache directory with proper error handling
    private func createCacheDirectoryIfNeeded() {
        do {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            AppLogger.error("Failed to create avatar cache directory at \(cacheDirectory.path): \(error.localizedDescription)")
        }
    }
    
    func getCachedImage(for userId: String, from url: URL) async -> NSImage? {
        let cacheURL = cacheFileURL(for: userId)
        let metadataURL = metadataFileURL(for: userId)

        // Check if file and metadata exist
        guard fileManager.fileExists(atPath: cacheURL.path),
              let metadata = loadMetadata(from: metadataURL) else {
            return nil
        }

        // Check if cache has expired
        let now = Date()
        if now.timeIntervalSince(metadata.cachedAt) > cacheExpirationInterval {
            removeCacheFiles(cacheURL: cacheURL, metadataURL: metadataURL, reason: "expired")
            return nil
        }

        // Check if URL has changed
        if metadata.originalURL != url.absoluteString {
            removeCacheFiles(cacheURL: cacheURL, metadataURL: metadataURL, reason: "URL changed")
            return nil
        }

        // Load image from cache
        guard let imageData = try? Data(contentsOf: cacheURL),
              let image = NSImage(data: imageData) else {
            return nil
        }

        return image
    }

    /// Removes cache files with proper error handling
    /// - Parameters:
    ///   - cacheURL: URL of the cached image file
    ///   - metadataURL: URL of the metadata file
    ///   - reason: Reason for removal (for logging)
    private func removeCacheFiles(cacheURL: URL, metadataURL: URL, reason: String) {
        do {
            try fileManager.removeItem(at: cacheURL)
        } catch {
            AppLogger.error("Failed to remove cached avatar at \(cacheURL.path) (\(reason)): \(error.localizedDescription)")
        }

        do {
            try fileManager.removeItem(at: metadataURL)
        } catch {
            AppLogger.error("Failed to remove avatar metadata at \(metadataURL.path) (\(reason)): \(error.localizedDescription)")
        }
    }
    
    func cacheImage(_ image: NSImage, for userId: String, from url: URL) async {
        let cacheURL = cacheFileURL(for: userId)
        let metadataURL = metadataFileURL(for: userId)

        // Convert image to PNG
        guard let tiffData = image.tiffRepresentation,
              let pngData = NSBitmapImageRep(data: tiffData)?.representation(using: .png, properties: [:]) else {
            AppLogger.error("Failed to convert avatar to PNG for user \(userId)")
            return
        }

        // Save image
        do {
            try pngData.write(to: cacheURL)
        } catch {
            AppLogger.error("Failed to cache avatar for user \(userId) at \(cacheURL.path): \(error.localizedDescription)")
            return
        }

        // Save metadata
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

        // Rate limiting: wait for available slot
        downloadSemaphore.wait()
        defer { downloadSemaphore.signal() }

        // Load from network
        do {
            let (data, response) = try await Self.urlSession.data(from: url)

            // Validate response
            guard let httpResponse = response as? HTTPURLResponse else {
                AppLogger.error("Invalid response type for avatar URL: \(url.absoluteString)")
                return nil
            }

            guard httpResponse.statusCode == 200 else {
                AppLogger.error("Avatar load failed with status \(httpResponse.statusCode) for URL: \(url.absoluteString)")
                return nil
            }

            // Validate size from Content-Length header
            if let contentLengthStr = httpResponse.value(forHTTPHeaderField: "Content-Length"),
               let contentLength = Int64(contentLengthStr),
               contentLength > Self.maxAvatarSize {
                AppLogger.error("Avatar size (\(contentLength) bytes) exceeds limit (\(Self.maxAvatarSize) bytes) for user \(userId)")
                return nil
            }

            // Validate actual data size
            if Int64(data.count) > Self.maxAvatarSize {
                AppLogger.error("Downloaded avatar size (\(data.count) bytes) exceeds limit (\(Self.maxAvatarSize) bytes) for user \(userId)")
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
                AppLogger.error("Timeout while loading avatar for user \(userId) from \(url.absoluteString)")
            default:
                AppLogger.error("Network error loading avatar for user \(userId): \(error.localizedDescription)")
            }
            return nil

        } catch {
            AppLogger.error("Unexpected error loading avatar for user \(userId): \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Sanitizes userId to prevent path traversal attacks
    /// Only allows alphanumeric characters, hyphens, and underscores
    private func sanitizeUserId(_ userId: String) -> String {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitized = userId.unicodeScalars.filter { allowedCharacters.contains($0) }
        let result = String(String.UnicodeScalarView(sanitized))

        // If sanitization removed everything, use a hash of the original
        if result.isEmpty {
            return String(userId.hashValue)
        }

        return result
    }

    private func cacheFileURL(for userId: String) -> URL {
        let sanitized = sanitizeUserId(userId)
        return cacheDirectory.appendingPathComponent("\(sanitized).png")
    }

    private func metadataFileURL(for userId: String) -> URL {
        let sanitized = sanitizeUserId(userId)
        return cacheDirectory.appendingPathComponent("\(sanitized).metadata.json")
    }
    
    private func loadMetadata(from url: URL) -> CacheMetadata? {
        guard let data = try? Data(contentsOf: url),
              let metadata = try? Self.metadataDecoder.decode(CacheMetadata.self, from: data) else {
            return nil
        }
        return metadata
    }
    
    private func saveMetadata(_ metadata: CacheMetadata, to url: URL) {
        do {
            let data = try Self.metadataEncoder.encode(metadata)
            try data.write(to: url)
        } catch {
            AppLogger.error("Failed to save avatar metadata at \(url.path): \(error.localizedDescription)")
        }
    }

    func clearCache() {
        do {
            try fileManager.removeItem(at: cacheDirectory)
            AppLogger.info("Avatar cache cleared at \(cacheDirectory.path)")
        } catch {
            AppLogger.error("Failed to clear avatar cache at \(cacheDirectory.path): \(error.localizedDescription)")
        }

        createCacheDirectoryIfNeeded()
    }
}

private struct CacheMetadata: Codable {
    let cachedAt: Date
    let originalURL: String
}

