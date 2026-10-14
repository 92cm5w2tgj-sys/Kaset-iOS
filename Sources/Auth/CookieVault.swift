import Foundation
import Security

/// Where the cookie archive lives between launches.
protocol CookieVault: Sendable {
    func load() -> Data?
    @discardableResult func save(_ data: Data) -> Bool
    @discardableResult func delete() -> Bool
}

/// Keychain, this device only, readable after the first unlock (so background refreshes work).
struct KeychainCookieVault: CookieVault {
    var service = "dev.emoona.kaset.auth"
    var account = "youtube-music-cookies"

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: self.account,
        ]
    }

    func load() -> Data? {
        var query = self.query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    func save(_ data: Data) -> Bool {
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(self.query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }

        var add = self.query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    func delete() -> Bool {
        let status = SecItemDelete(self.query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

/// For tests.
final class InMemoryCookieVault: CookieVault, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?

    func load() -> Data? { self.lock.withLock { self.data } }
    func save(_ data: Data) -> Bool { self.lock.withLock { self.data = data; return true } }
    func delete() -> Bool { self.lock.withLock { self.data = nil; return true } }
}
