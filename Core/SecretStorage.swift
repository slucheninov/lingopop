import Foundation
import CryptoKit
import IOKit
import os

enum SecretStorage {

    private static let log = Logger(subsystem: "com.lingopop.app", category: "SecretStorage")
    private static let salt = "LingoPop.v1.secrets"
    private static let flagPrefix = "LingoPop.secretHas."

    private static var fileURL: URL {
        let fm = FileManager.default
        let support = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let folder = support.appendingPathComponent("LingoPop", isDirectory: true)
        if !fm.fileExists(atPath: folder.path) {
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder.appendingPathComponent("secrets.dat")
    }

    private static var symmetricKey: SymmetricKey {
        let identifier = machineIdentifier() + "|" + salt
        let digest = SHA256.hash(data: Data(identifier.utf8))
        return SymmetricKey(data: digest)
    }

    private static func machineIdentifier() -> String {
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard entry != 0 else { return "fallback-machine-id" }
        defer { IOObjectRelease(entry) }
        guard let uuid = IORegistryEntryCreateCFProperty(entry, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String else {
            return "fallback-machine-id"
        }
        return uuid
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
            try combined.write(to: fileURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            return true
        } catch {
            log.error("Encrypt failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
