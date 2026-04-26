import XCTest
import AppKit
@testable import MegaplanHepler

/// Unit tests for AvatarCacheManager public size/count APIs
final class AvatarCacheManagerTests: XCTestCase {

    private var manager: AvatarCacheManager!
    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MegaplanHelperTests-\(UUID().uuidString)", isDirectory: true)
        manager = AvatarCacheManager(cacheDirectory: tmpDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
        manager = nil
        tmpDir = nil
    }

    func testCacheSize_EmptyCache_ReturnsZero() async {
        let size = await manager.cacheSize()
        XCTAssertEqual(size, 0, "Empty cache must report size 0")
    }

    func testEntryCount_EmptyCache_ReturnsZero() async {
        let count = await manager.entryCount()
        XCTAssertEqual(count, 0, "Empty cache must report 0 entries")
    }

    func testEntryCount_AfterSingleCacheImage_ReturnsOne() async {
        let image = NSImage(size: NSSize(width: 32, height: 32))
        let url = URL(string: "https://example.com/avatar.png")!
        await manager.cacheImage(image, for: "test-user-1", from: url)

        let count = await manager.entryCount()
        XCTAssertEqual(count, 1, "After caching exactly one avatar, entryCount must be 1")

        let size = await manager.cacheSize()
        XCTAssertGreaterThan(size, 0, "Cached avatar must contribute non-zero size")
    }
}
