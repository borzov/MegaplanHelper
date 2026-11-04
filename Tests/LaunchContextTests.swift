import XCTest
@testable import MegaplanHepler

final class LaunchContextTests: XCTestCase {
    func testUnitTestHostIsDetected() {
        XCTAssertTrue(LaunchContext.isUnitTestHost)
    }
}
