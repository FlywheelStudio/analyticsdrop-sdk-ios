import Foundation
import Security

/// Owns the anonymous device id (persisted in the Keychain so it survives reinstall on the same
/// device — acceptable for the POC, §3.4) and the customer-supplied external user id (in memory).
final class IdentityManager {
    static let defaultService = "dev.analyticsdrop.sdk"
    private static let account = "anonymousId"

    private let service: String

    private(set) var anonymousId: String
    private(set) var externalUserId: String?

    /// - Parameter service: Keychain service name. Tests inject a unique one so they never touch
    ///   the real id.
    init(service: String = IdentityManager.defaultService) {
        self.service = service
        if let existing = Self.keychainRead(service: service, account: Self.account) {
            anonymousId = existing
        } else {
            anonymousId = Self.rotatePersistedId(service: service)
        }
    }

    func identify(_ userId: String) {
        externalUserId = userId
    }

    /// Forget the external user and start a new anonymous identity (decision 005). Without the
    /// rotation, the next account on this device would share an `anonymousId` with the last one,
    /// and the server's identity stitching would fold their histories together.
    func reset() {
        externalUserId = nil
        anonymousId = Self.rotatePersistedId(service: service)
    }

    /// Write a fresh anonymous id to the Keychain and return it. Also used by `Core.reset()` when
    /// no `IdentityManager` exists (before `start()`, or while opted out), so the next one reads
    /// the new id.
    @discardableResult
    static func rotatePersistedId(service: String = IdentityManager.defaultService) -> String {
        let fresh = UUID().uuidString
        keychainWrite(fresh, service: service, account: account)
        return fresh
    }

    /// The persisted id, if any (test support).
    static func persistedId(service: String = IdentityManager.defaultService) -> String? {
        keychainRead(service: service, account: account)
    }

    /// Remove the persisted id (test support).
    static func deletePersistedId(service: String) {
        SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
    }

    // MARK: - Keychain

    private static func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func keychainRead(service: String, account: String) -> String? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }
        return value
    }

    /// Update-or-add. A bare `SecItemAdd` over an existing item fails with `errSecDuplicateItem`,
    /// which would leave the old id in place for the next launch after a `reset()`.
    private static func keychainWrite(_ value: String, service: String, account: String) {
        let query = baseQuery(service: service, account: account)
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard status == errSecItemNotFound else { return }
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attrs as CFDictionary, nil)
    }
}
