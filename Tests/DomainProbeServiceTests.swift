import XCTest
@testable import MegaplanHepler

final class DomainProbeServiceTests: XCTestCase {

    override func tearDown() {
        URLProtocolMock.handler = nil
        super.tearDown()
    }

    func testProbe_ValidDomainReturns200_ResolvesToOnline() async {
        URLProtocolMock.handler = { request in
            XCTAssertEqual(request.httpMethod, "HEAD")
            XCTAssertEqual(request.url?.path, "/api/version")
            let response = HTTPURLResponse(url: request.url!,
                                           statusCode: 200,
                                           httpVersion: "HTTP/1.1",
                                           headerFields: nil)!
            return (response, nil)
        }
        let service = DomainProbeService(session: URLProtocolMock.makeSession())

        let state = await service.probe("acme.megaplan.ru")

        guard case .online(let info) = state else {
            return XCTFail("expected .online, got \(state)")
        }
        XCTAssertEqual(info.canonicalDomain, "acme.megaplan.ru")
    }

    func testProbe_BlockedHost_ResolvesToBlocked() async {
        let service = DomainProbeService(session: URLProtocolMock.makeSession())
        let state = await service.probe("localhost")
        XCTAssertEqual(state, .blocked)
    }

    func testProbe_InvalidDomain_ResolvesToInvalid() async {
        let service = DomainProbeService(session: URLProtocolMock.makeSession())
        let state = await service.probe("not a domain at all !!!")
        XCTAssertEqual(state, .invalid)
    }

    func testProbe_NetworkError_ResolvesToUnreachable() async {
        URLProtocolMock.handler = { _ in
            throw URLError(.cannotConnectToHost)
        }
        let service = DomainProbeService(session: URLProtocolMock.makeSession())
        let state = await service.probe("acme.megaplan.ru")
        XCTAssertEqual(state, .unreachable)
    }

    func testProbe_5xxResponse_ResolvesToUnreachable() async {
        URLProtocolMock.handler = { request in
            let response = HTTPURLResponse(url: request.url!,
                                           statusCode: 503,
                                           httpVersion: "HTTP/1.1",
                                           headerFields: nil)!
            return (response, nil)
        }
        let service = DomainProbeService(session: URLProtocolMock.makeSession())
        let state = await service.probe("acme.megaplan.ru")
        XCTAssertEqual(state, .unreachable)
    }

    func testProbe_SecondCallForSameDomainHitsCache_HandlerCalledOnce() async {
        var callCount = 0
        URLProtocolMock.handler = { request in
            callCount += 1
            let response = HTTPURLResponse(url: request.url!,
                                           statusCode: 200,
                                           httpVersion: "HTTP/1.1",
                                           headerFields: nil)!
            return (response, nil)
        }
        let service = DomainProbeService(session: URLProtocolMock.makeSession())

        _ = await service.probe("acme.megaplan.ru")
        _ = await service.probe("acme.megaplan.ru")

        XCTAssertEqual(callCount, 1, "second call must be served from cache")
    }

    func testProbe_UnreachableResult_IsNotCached_HandlerCalledTwice() async {
        var callCount = 0
        URLProtocolMock.handler = { _ in
            callCount += 1
            throw URLError(.cannotConnectToHost)
        }
        let service = DomainProbeService(session: URLProtocolMock.makeSession())

        _ = await service.probe("acme.megaplan.ru")
        _ = await service.probe("acme.megaplan.ru")

        XCTAssertEqual(callCount, 2, "unreachable results must not be cached so retry works after network recovery")
    }
}
