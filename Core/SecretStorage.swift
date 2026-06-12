import Foundation
import CryptoKit
import IOKit
import os

enum SecretStorage {

    private static let log = Logger(subsystem: "com.lingopop.app", category: "SecretStorage")
    private static let flagPrefix = "LingoPop.secretHas."

    // Single shared folder, created with 0700 permissions on first access.
    private static var folderURL: URL {
        let fm = FileManager.default
        let support = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let folder = support.appendingPathComponent("LingoPop", isDirectory: true)
        if !fm.fileExists(atPath: folder.path) {
            do {
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
            } catch {
                log.error("Failed to create LingoPop directory: \(error.localizedDescription, privacy: .public)")
            }
        }
        return folder
    }

    private static var fileURL: URL { folderURL.appendingPathComponent("secrets.dat") }
    private static var machineKeyURL: URL { folderURL.appendingPathComponent("machine.key") }

    // H-1: HKDF-derived key using a persisted random salt (secrets.salt).
    private static var symmetricKey: SymmetricKey {
        let saltData = loadOrCreateSalt()
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(machineIdentifier().utf8)),
            salt: saltData,
            info: Data("LingoPop.v1.secrets".utf8),
            outputByteCount: 32
        )
    }

    private static func loadOrCreateSalt() -> Data {
        let saltURL = folderURL.appendingPathComponent("secrets.salt")
        if let existing = try? Data(contentsOf: saltURL), existing.count == 32 {
            return existing
        }
        var randomBytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes) == errSecSuccess else {
            log.error("SecRandomCopyBytes failed for HKDF salt; key will be unstable")
            return Data(SHA256.hash(data: Data(UUID().uuidString.utf8)))
        }
        let saltData = Data(randomBytes)
        let tmpURL = folderURL.appendingPathComponent("secrets.salt.tmp")
        do {
            try saltData.write(to: tmpURL)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmpURL.path)
            try FileManager.default.moveItem(at: tmpURL, to: saltURL)
        } catch {
            log.error("Failed to persist secrets.salt: \(error.localizedDescription, privacy: .public)")
        }
        return saltData
    }

    private static func machineIdentifier() -> String {
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        if entry != 0 {
            defer { IOObjectRelease(entry) }
            if let uuid = IORegistryEntryCreateCFProperty(entry, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
                return uuid
            }
        }
        // IOKit unavailable — use (or generate) a persisted random machine secret.
        let keyURL = machineKeyURL
        if let existing = try? Data(contentsOf: keyURL), !existing.isEmpty {
            return existing.base64EncodedString()
        }
        var randomBytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes) == errSecSuccess else {
            log.error("SecRandomCopyBytes failed; machine identifier will be unstable")
            return UUID().uuidString
        }
        let keyData = Data(randomBytes)
        do {
            try keyData.write(to: keyURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
        } catch {
            log.error("Failed to persist machine.key: \(error.localizedDescription, privacy: .public)")
        }
        return keyData.base64EncodedString()
    }

    static func get(_ key: String) -> String? {
        let store = loadAll()
        return store[key]
    }

    static func hasKey(_ key: String) -> Bool {
        UserDefaults.standard.bool(forKey: flagPrefix + key)
    }

    @discardableResult
    static func set(_ value: String, for key: String) -> Bool {
        var store = loadAll()
        store[key] = value
        let ok = saveAll(store)
        if ok {
            UserDefaults.standard.set(true, forKey: flagPrefix + key)
        }
        return ok
    }

    @discardableResult
    static func delete(_ key: String) -> Bool {
        var store = loadAll()
        store.removeValue(forKey: key)
        let ok = saveAll(store)
        if ok {
            UserDefaults.standard.removeObject(forKey: flagPrefix + key)
        }
        return ok
    }

    private static func loadAll() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        do {
            let box = try AES.GCM.SealedBox(combined: data)
            let plaintext = try AES.GCM.open(box, using: symmetricKey)
            return (try JSONDecoder().decode([String: String].self, from: plaintext))
        } catch {
            log.error("Decrypt failed: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }

    private static func saveAll(_ store: [String: String]) -> Bool {
        do {
            let plaintext = try JSONEncoder().encode(store)
            let sealed = try AES.GCM.seal(plaintext, using: symmetricKey)
            guard let combined = sealed.combined else { return false }
            // H-2: write → chmod → rename, eliminating the open-permissions window.
            let finalURL = fileURL
            let tmpURL = folderURL.appendingPathComponent("secrets.dat.tmp")
            let fm = FileManager.default
            try combined.write(to: tmpURL)
            do {
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmpURL.path)
            } catch {
                log.error("Failed to set 0600 on secrets.dat.tmp: \(error.localizedDescription, privacy: .public)")
            }
            if fm.fileExists(atPath: finalURL.path) {
                try fm.removeItem(at: finalURL)
            }
            try fm.moveItem(at: tmpURL, to: finalURL)
            return true
        } catch {
            log.error("Encrypt failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
