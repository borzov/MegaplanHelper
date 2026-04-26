import Foundation

actor DomainProbeService {
    private let session: URLSession
    private let timeout: TimeInterval
    private var cache: [String: DomainProbeState] = [:]

    init(session: URLSession = .shared, timeout: TimeInterval = 4.0) {
        self.session = session
        self.timeout = timeout
    }

    func clearCache() {
        cache.removeAll()
    }

    func probe(_ domain: String) async -> DomainProbeState {
        let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return .invalid }

        if let cached = cache[trimmed] { return cached }

        guard let baseURL = URLValidator.validateDomain(trimmed) else {
            let host = stripScheme(trimmed)
            let state: DomainProbeState = URLValidator.isBlockedHost(host) ? .blocked : .invalid
            cache[trimmed] = state
            return state
        }

        let probeURL = baseURL.appendingPathComponent("api/version")
        var request = URLRequest(url: probeURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        let state: DomainProbeState
        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse,
               (200..<400).contains(http.statusCode) {
                let info = WorkspaceInfo(canonicalDomain: baseURL.host ?? trimmed,
                                         displayName: nil,
                                         faviconURL: baseURL.appendingPathComponent("favicon.ico"),
                                         supportsSSO: false)
                state = .online(info)
            } else {
                state = .unreachable
            }
        } catch {
            state = .unreachable
        }

        cache[trimmed] = state
        return state
    }

    private nonisolated func stripScheme(_ s: String) -> String {
        if s.hasPrefix("https://") { return String(s.dropFirst("https://".count)) }
        if s.hasPrefix("http://")  { return String(s.dropFirst("http://".count)) }
        return s
    }
}
