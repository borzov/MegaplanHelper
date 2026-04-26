import XCTest
@testable import MegaplanHepler

@MainActor
final class AppStateFormattersTests: XCTestCase {

    /// We only test the nil-path here. The non-nil branch of
    /// `AppState.formattedLastSync` is a thin pass-through to
    /// `DateFormatters.relative`, which is fully covered by
    /// `DateFormattersExtTests`. Re-testing it via AppState would
    /// require either a public setter for `lastSyncTime` (breaks
    /// encapsulation) or a fully mocked refresh path (over-engineered
    /// for one line of glue).
    func testFormattedLastSync_NilLastSync_ReturnsNil() async {
        let appState = AppState()
        XCTAssertNil(appState.formattedLastSync)
    }
}
