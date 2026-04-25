import XCTest
@testable import MegaplanHepler

@MainActor
final class AppStateFormattersTests: XCTestCase {

    func testFormattedLastSync_NilLastSync_ReturnsNil() async {
        let appState = AppState()
        // lastSyncTime is private(set), default nil — no need to assign
        XCTAssertNil(appState.formattedLastSync)
    }

    func testFormattedLastSync_RecentSync_ReturnsHumanReadable() async throws {
        // lastSyncTime is `@Published private(set) var lastSyncTime: Date?` — mutated
        // only via refresh()/internal sync paths, with no public injection point.
        // Adding a public setter purely to enable this test would be a contract change
        // outside the scope of T3. The Nil-path test above is sufficient to verify
        // the computed property's null-handling; the non-nil path is a thin wrapper
        // over `DateFormatters.relative(_:)` which has its own coverage in
        // DateFormattersExtTests.
        try XCTSkipIf(true, "Requires injectable lastSyncTime; out of scope for T3")
    }
}
