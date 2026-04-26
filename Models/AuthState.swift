import Foundation

enum AuthFormStep: Hashable {
    case domain
    case credentials(domain: String, info: WorkspaceInfo?)
}

struct WorkspaceInfo: Equatable, Hashable {
    let canonicalDomain: String
    let displayName: String?
    let faviconURL: URL?
    let supportsSSO: Bool
}

enum DomainProbeState: Equatable {
    case idle
    case probing
    case online(WorkspaceInfo)
    case unreachable
    case blocked
    case invalid
}

struct LockoutState: Equatable {
    let lockedUntil: Date
    let attemptCount: Int

    var remainingSeconds: TimeInterval {
        max(0, lockedUntil.timeIntervalSinceNow)
    }

    var isActive: Bool { remainingSeconds > 0 }
}

enum AuthFieldError: Equatable {
    enum DomainReason: Equatable {
        case invalidFormat
        case blocked
        case unreachable
    }

    enum CredentialsReason: Equatable {
        case invalidEmail
        case emptyPassword
        case unauthorized
        case serverError(String)
    }

    case domain(DomainReason)
    case credentials(CredentialsReason)
    case lockout

    var localizedDescription: String {
        switch self {
        case .domain(.invalidFormat):
            return String(localized: "auth.error.invalidDomain")
        case .domain(.blocked):
            return String(localized: "auth.error.blockedDomain")
        case .domain(.unreachable):
            return String(localized: "auth.error.unreachableDomain")
        case .credentials(.invalidEmail):
            return String(localized: "auth.error.invalidEmail")
        case .credentials(.emptyPassword):
            return String(localized: "auth.error.emptyPassword")
        case .credentials(.unauthorized):
            return String(localized: "auth.error.unauthorized")
        case .credentials(.serverError(let message)):
            return message
        case .lockout:
            return String(localized: "auth.error.tooManyAttempts")
        }
    }
}

enum AuthFieldFocus: Hashable {
    case domain
    case login
    case password
}
