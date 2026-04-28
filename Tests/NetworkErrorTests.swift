import XCTest
@testable import MegaplanHepler

final class NetworkErrorTests: XCTestCase {

    func testInit_WithTimedOutURLError_MapsToTimedOutCase() {
        let error = NetworkError(URLError(.timedOut))
        XCTAssertEqual(error.id, NetworkError.timedOut.id)
    }

    func testErrorDescription_TimedOut_UsesTimeoutLocalization() {
        let expected = String(localized: "error.timeout")
        XCTAssertEqual(NetworkError.timedOut.localizedDescription, expected)
    }
}
