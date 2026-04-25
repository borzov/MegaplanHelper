import XCTest
import AppKit
@testable import MegaplanHepler

/// Unit tests for AvatarCacheManager public size/count APIs
final class AvatarCacheManagerTests: XCTestCase {

    func testCacheSize_EmptyCache_ReturnsZero() async {
        let manager = AvatarCacheManager.shared
        manager.clearCache()

        let size = await manager.cacheSize()
        XCTAssertEqual(size, 0, "Empty cache must report size 0")
    }

    func testEntryCount_EmptyCache_ReturnsZero() async {
        let manager = AvatarCacheManager.shared
        manager.clearCache()

        let count = await manager.entryCount()
        XCTAssertEqual(count, 0, "Empty cache must report 0 entries")
    }

    func testEntryCount_AfterSingleCacheImage_ReturnsOne() async {
        let manager = AvatarCacheManager.shared
        manager.clearCache()

        let image = NSImage(size: NSSize(width: 32, height: 32))
        let url = URL(string: "https://example.com/avatar.png")!
        await manager.cacheImage(image, for: "test-user-1", from: url)

        let count = await manager.entryCount()
        XCTAssertGreaterThanOrEqual(count, 1, "After caching, entryCount must be >= 1")
    }
}
