import XCTest
@testable import MegaplanHepler

@MainActor
final class AppStateLoadSavedCredentialsTests: XCTestCase {

    func testLoadSavedCredentials_EmptyInputs_ReturnsNil() async {
        let suiteName = "test-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }
        let state = AppState(userDefaults: suite)
        let result = await state.loadSavedCredentialsFromKeychain(domain: "", login: "")
        XCTAssertNil(result)
    }

    func testLoadSavedCredentials_DomainOrLoginMismatch_ReturnsNil() async {
        let suiteName = "test-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }
        suite.set("acme.megaplan.ru", forKey: "megaplan.domain")
        suite.set("alice@acme.com", forKey: "megaplan.username")
        let state = AppState(userDefaults: suite)

        let differentDomain = await state.loadSavedCredentialsFromKeychain(
            domain: "other.megaplan.ru", login: "alice@acme.com")
        XCTAssertNil(differentDomain)

        let differentLogin = await state.loadSavedCredentialsFromKeychain(
            domain: "acme.megaplan.ru", login: "bob@acme.com")
        XCTAssertNil(differentLogin)
    }
}
