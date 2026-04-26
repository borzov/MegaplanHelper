import XCTest
@testable import MegaplanHepler

final class AuthStateTests: XCTestCase {

    func testAuthFormStep_DomainEqualsDomain() {
        XCTAssertEqual(AuthFormStep.domain, AuthFormStep.domain)
    }

    func testAuthFormStep_CredentialsWithSameDomainAndInfoAreEqual() {
        let info = WorkspaceInfo(canonicalDomain: "acme.megaplan.ru",
                                 displayName: "ACME",
                                 faviconURL: nil,
                                 supportsSSO: false)
        let a = AuthFormStep.credentials(domain: "acme.megaplan.ru", info: info)
        let b = AuthFormStep.credentials(domain: "acme.megaplan.ru", info: info)
        XCTAssertEqual(a, b)
    }

    func testAuthFormStep_CredentialsWithDifferentDomainsAreNotEqual() {
        let a = AuthFormStep.credentials(domain: "acme.megaplan.ru", info: nil)
        let b = AuthFormStep.credentials(domain: "other.megaplan.ru", info: nil)
        XCTAssertNotEqual(a, b)
    }

    func testDomainProbeState_OnlineCarriesWorkspaceInfo() {
        let info = WorkspaceInfo(canonicalDomain: "acme.megaplan.ru",
                                 displayName: nil,
                                 faviconURL: nil,
                                 supportsSSO: false)
        let state = DomainProbeState.online(info)
        guard case .online(let captured) = state else {
            return XCTFail("expected .online")
        }
        XCTAssertEqual(captured, info)
    }

    func testLockoutState_RemainingSecondsIsPositiveBeforeExpiry() {
        let until = Date().addingTimeInterval(30)
        let lockout = LockoutState(lockedUntil: until, attemptCount: 3)
        XCTAssertGreaterThan(lockout.remainingSeconds, 0)
    }

    func testLockoutState_RemainingSecondsIsZeroAfterExpiry() {
        let until = Date().addingTimeInterval(-1)
        let lockout = LockoutState(lockedUntil: until, attemptCount: 3)
        XCTAssertEqual(lockout.remainingSeconds, 0)
    }

    func testAuthFieldError_HasLocalizedDescriptionForEveryCase() {
        let cases: [AuthFieldError] = [
            .domain(.invalidFormat),
            .domain(.blocked),
            .domain(.unreachable),
            .credentials(.invalidEmail),
            .credentials(.emptyPassword),
            .credentials(.unauthorized),
            .credentials(.serverError("boom")),
            .lockout
        ]
        for error in cases {
            XCTAssertFalse(error.localizedDescription.isEmpty,
                           "Missing description for \(error)")
        }
    }
}
