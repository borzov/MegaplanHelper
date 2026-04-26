import XCTest
@testable import MegaplanHepler

@MainActor
final class AppStateLockoutTests: XCTestCase {

    func testLockoutState_FreshAppState_IsNil() {
        let suiteName = "test-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }
        let state = AppState(userDefaults: suite)
        XCTAssertNil(state.lockoutState)
    }
}
