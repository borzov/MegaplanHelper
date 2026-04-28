import Foundation

enum NetworkError: LocalizedError, Identifiable {
    case invalidURL
    case unauthorized
    case decodingFailed
    case timedOut
    case transport(message: String)
    case server(message: String)
    case missingToken
    case validationFailed
    case autoLaunchFailure
    case sessionExpired
    case tooManyAttempts
    case offline

    var id: String {
        switch self {
        case .invalidURL: return "invalidURL"
        case .unauthorized: return "unauthorized"
        case .decodingFailed: return "decodingFailed"
        case .timedOut: return "timedOut"
        case .transport: return "transport"
        case .server: return "server"
        case .missingToken: return "missingToken"
        case .validationFailed: return "validationFailed"
        case .autoLaunchFailure: return "autoLaunchFailure"
        case .sessionExpired: return "sessionExpired"
        case .tooManyAttempts: return "tooManyAttempts"
        case .offline: return "offline"
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return String(localized: "error.invalidURL")
        case .unauthorized:
            return String(localized: "error.unauthorized")
        case .decodingFailed:
            return String(localized: "error.decoding")
        case .timedOut:
            return String(localized: "error.timeout")
        case .transport(let message):
            return String(format: String(localized: "error.transport"), message)
        case .server(let message):
            return String(format: String(localized: "error.server"), message)
        case .missingToken:
            return String(localized: "error.missingToken")
        case .validationFailed:
            return String(localized: "error.validation")
        case .autoLaunchFailure:
            return String(localized: "error.autoLaunch")
        case .sessionExpired:
            return String(localized: "error.sessionExpired")
        case .tooManyAttempts:
            return String(localized: "error.tooManyAttempts")
        case .offline:
            return String(localized: "error.offline")
        }
    }

    init(_ error: Error) {
        if let networkError = error as? NetworkError {
            self = networkError
            return
        }

        if let urlError = error as? URLError {
            if urlError.code == .timedOut {
                self = .timedOut
                return
            }
            self = .transport(message: urlError.localizedDescription)
            return
        }

        self = .server(message: error.localizedDescription)
    }
}
