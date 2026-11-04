import Foundation

protocol KeychainStoring: Sendable {
    func save(_ value: String, service: String, account: String) throws
    func read(service: String, account: String) throws -> String?
    func delete(service: String, account: String) throws
}

extension KeychainManager: KeychainStoring {}

final class InMemoryKeychain: KeychainStoring, @unchecked Sendable {
    private var storage: [String: String] = [:]
    private func key(service: String, account: String) -> String { "\(service)\n\(account)" }
    func save(_ value: String, service: String, account: String) throws { storage[key(service: service, account: account)] = value }
    func read(service: String, account: String) throws -> String? { storage[key(service: service, account: account)] }
    func delete(service: String, account: String) throws { storage.removeValue(forKey: key(service: service, account: account)) }
}
