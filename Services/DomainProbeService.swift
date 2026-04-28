import Foundation

actor DomainProbeService {
    private struct CachedProbe {
        let state: DomainProbeState
        let probedAt: Date
    }

    private let session: URLSession
    private let timeout: TimeInterval
    private let positiveTTL: TimeInterval
    private let negativeTTL: TimeInterval
    private var cache: [String: CachedProbe] = [:]

    init(
        session: URLSession = .shared,
        timeout: TimeInterval = 4.0,
        positiveTTL: TimeInterval = Constants.DomainProbeConfig.positiveTTL,
        negativeTTL: TimeInterval = Constants.DomainProbeConfig.negativeTTL
    ) {
        self.session = session
        self.timeout = timeout
        self.positiveTTL = positiveTTL
        self.negativeTTL = negativeTTL
    }

    func clearCache() {
        cache.removeAll()
    }

    func probe(_ domain: String) async -> DomainProbeState {
        let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return .invalid }

        if let cached = cache[trimmed], !isExpired(cached) {
            return cached.state
        }

        guard let baseURL = URLValidator.validateDomain(trimmed) else {
            let host = stripScheme(trimmed)
            let state: DomainProbeState = URLValidator.isBlockedHost(host) ? .blocked : .invalid
            cache[trimmed] = CachedProbe(state: state, probedAt: Date())
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
            if response is HTTPURLResponse {
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

        cache[trimmed] = CachedProbe(state: state, probedAt: Date())
        return state
    }

    private func isExpired(_ cached: CachedProbe) -> Bool {
        let ttl: TimeInterval
        switch cached.state {
        case .unreachable:
            ttl = negativeTTL
        default:
            ttl = positiveTTL
        }

        return Date().timeIntervalSince(cached.probedAt) > ttl
    }

    private nonisolated func stripScheme(_ s: String) -> String {
        if s.hasPrefix("https://") { return String(s.dropFirst("https://".count)) }
        if s.hasPrefix("http://")  { return String(s.dropFirst("http://".count)) }
        return s
    }
}
