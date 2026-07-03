import Foundation
import Security

/// Owns the anonymous device id (persisted in the Keychain so it survives reinstall on the same
/// device — acceptable for the POC, §3.4) and the customer-supplied external user id (in memory).
final class IdentityManager {
    private let service = "dev.wayfind.sdk"
    private let account = "anonymousId"

    let anonymousId: String
    private(set) var externalUserId: String?

    init() {
        if let existing = Self.keychainRead(service: service, account: account) {
            anonymousId = existing
        } else {
            let fresh = UUID().uuidString
            Self.keychainWrite(fresh, service: service, account: account)
            anonymousId = fresh
        }
    }

    func identify(_ userId: String) {
        externalUserId = userId
    }

    // MARK: - Keychain

    private static func keychainRead(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }
        return value
    }

    private static func keychainWrite(_ value: String, service: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attrs as CFDictionary, nil)
    }
}
