import Foundation
import Security

public protocol HueCredentialStore: Sendable {
    func load(alias: String) throws -> HueCredentials?
    func save(_ credentials: HueCredentials, alias: String) throws
    func remove(alias: String) throws
}

public struct KeychainHueCredentialStore: HueCredentialStore, Sendable {
    private let service: String
    private let accessGroup: String?

    public init(service: String = "com.adeze.HueEntertainmentKit", accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    public func load(alias: String) throws -> HueCredentials? {
        var query = baseQuery(alias: alias)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status) }
        return try JSONDecoder().decode(HueCredentials.self, from: data)
    }

    public func save(_ credentials: HueCredentials, alias: String) throws {
        let data = try JSONEncoder().encode(credentials)
        let query = baseQuery(alias: alias)
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insertion = query
            insertion[kSecValueData as String] = data
            let addStatus = SecItemAdd(insertion as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status)
        }
    }

    public func remove(alias: String) throws {
        let status = SecItemDelete(baseQuery(alias: alias) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status) }
    }

    private func baseQuery(alias: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: alias,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }
}

public struct KeychainError: Error, Equatable, Sendable {
    public let status: OSStatus
    public init(_ status: OSStatus) { self.status = status }
}
