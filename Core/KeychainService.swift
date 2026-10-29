import Foundation
import Security
import os

enum KeychainService {

    private static let service = "com.lingopop.app"
    private static let log = Logger(subsystem: "com.lingopop.app", category: "KeychainService")

    static func get(_ key: String) -> String? {
        SecretStorage.get(key)
    }

    static func hasKey(_ key: String) -> Bool {
        SecretStorage.hasKey(key)
    }

    @discardableResult
    static func set(_ value: String, for key: String) -> Bool {
        deleteLegacyKeychainItem(for: key)
        return SecretStorage.set(value, for: key)
    }

    @discardableResult
    static func delete(_ key: String) -> Bool {
        deleteLegacyKeychainItem(for: key)
        return SecretStorage.delete(key)
    }

    private static func deleteLegacyKeychainItem(for key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess {
            log.info("Deleted legacy keychain item: \(key, privacy: .public)")
        }
    }
}
