import Foundation

struct MegaplanCredentials: Codable, Equatable {
    var domain: String
    var login: String
    var password: String

    static let empty = MegaplanCredentials(domain: "", login: "", password: "")
}
