import XCTest
@testable import MegaplanHepler

@MainActor
final class AppStateLockoutTests: XCTestCase {

    func testLockoutState_FreshAppState_IsNil() {
        let suite = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        defer { UserDefaults.standard.removePersistentDomain(forName: suite.dictionaryRepresentation().description) }
        let state = AppState(userDefaults: suite)
        XCTAssertNil(state.lockoutState)
    }
}
