import Foundation
import Security

/// Small secret storage seam. The Spotify refresh token goes through it.
protocol SecretStore: Sendable {
    func read(_ key: String) -> String?
    /// Replaces any existing value. Returns false when the write failed.
    @discardableResult func write(_ value: String, for key: String) -> Bool
    func delete(_ key: String)
}

/// Keychain generic-password items, readable after first unlock, never synced or backed up to another device.
struct KeychainStore: SecretStore {
    private let service: String

    init(service: String = "Memorise.lyrics") { self.service = service }

    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
    }

    func read(_ key: String) -> String? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func write(_ value: String, for key: String) -> Bool {
        delete(key)
        var q = query(key)
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    func delete(_ key: String) {
        SecItemDelete(query(key) as CFDictionary)
    }
}

/// In-memory stand-in for previews.
final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func read(_ key: String) -> String? { lock.withLock { values[key] } }

    @discardableResult
    func write(_ value: String, for key: String) -> Bool {
        lock.withLock { values[key] = value }
        return true
    }

    func delete(_ key: String) { lock.withLock { _ = values.removeValue(forKey: key) } }
}
