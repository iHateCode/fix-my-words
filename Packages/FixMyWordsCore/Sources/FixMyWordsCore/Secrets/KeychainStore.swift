import Foundation
import Security

public struct KeychainStore: Sendable {
    public static let defaultService = "com.ihatecode.FixMyWords"
    let service: String
    let account = "openrouter-api-key"

    /// UI tests pass a different service, so they never read or delete the real key.
    public init(service: String = KeychainStore.defaultService) { self.service = service }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: kCFBooleanFalse!]      // this Mac only: never synced through iCloud Keychain
    }

    public func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Update first, add only if missing. Upstream's delete-then-add lost the key when the add failed.
    public func save(_ key: String) throws {
        let data = Data(key.utf8)
        let update: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    public func delete() { SecItemDelete(baseQuery as CFDictionary) }
}

public struct KeychainError: Error { public let status: OSStatus }
