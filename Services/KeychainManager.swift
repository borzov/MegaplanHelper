import Foundation
import Security

enum KeychainError: Error {
    case unexpectedStatus(OSStatus)
}

final class KeychainManager {
    func save(_ value: String, service: String, account: String) throws {
        let encodedValue = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        // Try to update existing item first (atomic operation)
        let updateAttributes: [String: Any] = [
            kSecValueData as String: encodedValue,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        var status = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)

        if status == errSecItemNotFound {
            // Item doesn't exist, create new one
            var addAttributes = query
            addAttributes[kSecValueData as String] = encodedValue
            addAttributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked

            status = SecItemAdd(addAttributes as CFDictionary, nil)
        }

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func read(service: String, account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status != errSecItemNotFound else {
            return nil
        }

        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedStatus(status)
        }

        return value
    }

    func delete(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
