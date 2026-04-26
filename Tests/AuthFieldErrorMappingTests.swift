import XCTest
@testable import MegaplanHepler

final class AuthFieldErrorMappingTests: XCTestCase {

    func testMapping_Unauthorized_BecomesCredentialsUnauthorized() {
        let mapped = AuthFieldError(networkError: .unauthorized)
        XCTAssertEqual(mapped, .credentials(.unauthorized))
    }

    func testMapping_TooManyAttempts_BecomesLockout() {
        let mapped = AuthFieldError(networkError: .tooManyAttempts)
        XCTAssertEqual(mapped, .lockout)
    }

    func testMapping_ValidationFailed_BecomesCredentialsInvalidEmail() {
        let mapped = AuthFieldError(networkError: .validationFailed)
        XCTAssertEqual(mapped, .credentials(.invalidEmail))
    }

    func testMapping_TransportError_BecomesDomainUnreachable() {
        let mapped = AuthFieldError(networkError: .transport(message: "down"))
        XCTAssertEqual(mapped, .domain(.unreachable))
    }

    func testMapping_OfflineError_BecomesDomainUnreachable() {
        let mapped = AuthFieldError(networkError: .offline)
        XCTAssertEqual(mapped, .domain(.unreachable))
    }

    func testMapping_InvalidURL_BecomesDomainUnreachable() {
        let mapped = AuthFieldError(networkError: .invalidURL)
        XCTAssertEqual(mapped, .domain(.unreachable))
    }

    func testMapping_ServerError_PreservesMessage() {
        let mapped = AuthFieldError(networkError: .server(message: "boom"))
        XCTAssertEqual(mapped, .credentials(.serverError("boom")))
    }
}
