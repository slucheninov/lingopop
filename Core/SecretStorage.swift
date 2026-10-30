import Foundation
import CryptoKit
import IOKit
import os

enum SecretStorage {

    private static let log = Logger(subsystem: "com.lingopop.app", category: "SecretStorage")
    private static let flagPrefix = "LingoPop.secretHas."
    // Persisted marker: an undecryptable secrets.dat was moved aside, so the provider settings it held are gone and
    // an empty store must not be mistaken for a trusted empty one (not even after a restart or after API keys were
    // re-entered into a new file). Deliberately NOT prefixed with `flagPrefix`, so `quarantineUnreadableFile` keeps it.
    // Cleared only by a successful `saveProviderSettings` (a deliberate provider edit).
    private static let quarantineMarkerKey = "LingoPop.providerSettingsLostToQuarantine"

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

    private enum SecretStorageError: Error {
        case randomGenerationFailed
        case saltPersistFailed
        case writeFailed
        case invalidSalt
    }

    // Derived key is cached after first derivation (guarded by `lock`).
    private static let lock = NSLock()
    // Mutable statics are only touched while holding `lock`.
    nonisolated(unsafe) private static var cachedKey: SymmetricKey?
    // True when machineIdentifier() had to generate a brand-new machine.key
    // (IOPlatformUUID unavailable); an existing secrets.dat can't match it.
    nonisolated(unsafe) private static var machineKeyWasFreshlyGenerated = false
    // Decrypted entries, kept after the first successful read/write so API keys and provider settings
    // are not re-decrypted on every access. Only set from a successful decrypt or write (guarded by `lock`).
    nonisolated(unsafe) private static var cachedEntries: [String: String]?

    // H-1: HKDF-derived key using a persisted random salt (secrets.salt).
    private static func symmetricKey() throws -> SymmetricKey {
        lock.lock()
        defer { lock.unlock() }
        if let cachedKey { return cachedKey }
        let saltData = try loadOrCreateSalt()
        let machine = try machineIdentifier()
        machineKeyWasFreshlyGenerated = machine.freshlyGenerated
        let key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(machine.id.utf8)),
            salt: saltData,
            info: Data("LingoPop.v1.secrets".utf8),
            outputByteCount: 32
        )
        cachedKey = key
        return key
    }

    /// Key scheme used before commit 1a04977: SHA256(IOPlatformUUID + "|" + salt string).
    private static func legacySymmetricKey() -> SymmetricKey {
        var uuid = "fallback-machine-id"
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        if entry != 0 {
            defer { IOObjectRelease(entry) }
            if let value = IORegistryEntryCreateCFProperty(entry, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
                uuid = value
            }
        }
        let digest = SHA256.hash(data: Data((uuid + "|" + "LingoPop.v1.secrets").utf8))
        return SymmetricKey(data: digest)
    }

    /// Writes `data` to `url` via a 0600 temp file and an atomic rename(2).
    private static func writeAtomically(_ data: Data, to url: URL) throws {
        let tmpURL = url.appendingPathExtension("tmp")
        let fm = FileManager.default
        try? fm.removeItem(at: tmpURL)
        guard fm.createFile(atPath: tmpURL.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw SecretStorageError.writeFailed
        }
        if rename(tmpURL.path, url.path) != 0 {
            try? fm.removeItem(at: tmpURL)
            throw SecretStorageError.writeFailed
        }
    }

    private static func loadOrCreateSalt() throws -> Data {
        let saltURL = folderURL.appendingPathComponent("secrets.salt")
        if let existing = try? Data(contentsOf: saltURL) {
            if existing.count == 32 { return existing }
            // Corrupt salt: regenerating would make an existing secrets.dat undecryptable.
            if FileManager.default.fileExists(atPath: fileURL.path) {
                log.error("secrets.salt has unexpected size \(existing.count) while secrets.dat exists; refusing to regenerate")
                throw SecretStorageError.invalidSalt
            }
        }
        var randomBytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes) == errSecSuccess else {
            log.error("SecRandomCopyBytes failed for HKDF salt")
            throw SecretStorageError.randomGenerationFailed
        }
        let saltData = Data(randomBytes)
        do {
            try writeAtomically(saltData, to: saltURL)
        } catch {
            log.error("Failed to persist secrets.salt: \(error.localizedDescription, privacy: .public)")
            throw SecretStorageError.saltPersistFailed
        }
        return saltData
    }

    private static func machineIdentifier() throws -> (id: String, freshlyGenerated: Bool) {
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        if entry != 0 {
            defer { IOObjectRelease(entry) }
            if let uuid = IORegistryEntryCreateCFProperty(entry, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
                return (uuid, false)
            }
        }
        // IOKit unavailable: use (or generate) a persisted random machine secret.
        let keyURL = machineKeyURL
        if let existing = try? Data(contentsOf: keyURL), !existing.isEmpty {
            return (existing.base64EncodedString(), false)
        }
        var randomBytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes) == errSecSuccess else {
            log.error("SecRandomCopyBytes failed for machine identifier")
            throw SecretStorageError.randomGenerationFailed
        }
        let keyData = Data(randomBytes)
        do {
            try writeAtomically(keyData, to: keyURL)
        } catch {
            log.error("Failed to persist machine.key: \(error.localizedDescription, privacy: .public)")
            throw SecretStorageError.saltPersistFailed
        }
        return (keyData.base64EncodedString(), true)
    }

    static func get(_ key: String) -> String? {
        guard case .available(let store) = loadAll() else { return nil }
        return store[key]
    }

    static func hasKey(_ key: String) -> Bool {
        UserDefaults.standard.bool(forKey: flagPrefix + key)
    }

    @discardableResult
    static func set(_ value: String, for key: String) -> Bool {
        guard case .available(var store) = loadAll() else {
            log.error("Secrets store unavailable; refusing to overwrite secrets.dat")
            return false
        }
        store[key] = value
        let ok = saveAll(store)
        if ok {
            UserDefaults.standard.set(true, forKey: flagPrefix + key)
        }
        return ok
    }

    @discardableResult
    static func delete(_ key: String) -> Bool {
        guard case .available(var store) = loadAll() else {
            log.error("Secrets store unavailable; refusing to overwrite secrets.dat")
            return false
        }
        store.removeValue(forKey: key)
        let ok = saveAll(store)
        if ok {
            UserDefaults.standard.removeObject(forKey: flagPrefix + key)
        }
        return ok
    }

    /// Provider settings (base URL, model, referer, region) stored next to the API keys in `secrets.dat`.
    /// `.unavailable` means the file could not be read / decrypted; callers must then leave old data untouched.
    /// `.quarantined` means the file was undecryptable and moved aside in this run (API keys must be re-entered, which
    /// still works); the provider settings it held are lost from the active store, so this is not a trusted empty store.
    static func loadProviderSettings() -> SecureProviderSettings {
        guard case .available(let store) = loadAll() else { return .unavailable }
        return SecretsPayload.providerSettings(in: store, lostToQuarantine: isProviderSettingsLostToQuarantine())
    }

    // UserDefaults is thread-safe, so no extra locking is needed for the persisted marker.
    private static func isProviderSettingsLostToQuarantine() -> Bool {
        UserDefaults.standard.bool(forKey: quarantineMarkerKey)
    }

    /// Sets the quarantine marker and forces it to disk. UserDefaults normally writes asynchronously and
    /// `synchronize()` is otherwise discouraged, but it is the only way to flush here, which is exactly what is
    /// needed: the marker must be durable before secrets.dat is moved aside. Also reads the value back.
    private static func markQuarantineDurably() -> Bool {
        setProviderSettingsLostToQuarantine(true)
        return UserDefaults.standard.synchronize() && isProviderSettingsLostToQuarantine()
    }

    private static func setProviderSettingsLostToQuarantine(_ value: Bool) {
        if value {
            UserDefaults.standard.set(true, forKey: quarantineMarkerKey)
        } else {
            UserDefaults.standard.removeObject(forKey: quarantineMarkerKey)
        }
    }

    /// Replaces the provider-settings entry; API keys and any unknown entries are preserved.
    @discardableResult
    static func saveProviderSettings(_ settings: [ProviderType: ProviderConnectionSettings]) -> Bool {
        guard case .available(var store) = loadAll() else {
            log.error("Secrets store unavailable; refusing to overwrite secrets.dat")
            return false
        }
        do {
            try SecretsPayload.setProviderSettings(settings, in: &store)
        } catch {
            log.error("Failed to encode provider settings: \(error.localizedDescription, privacy: .public)")
            return false
        }
        let ok = saveAll(store)
        if ok { setProviderSettingsLostToQuarantine(false) } // a deliberate write re-establishes a trusted store
        return ok
    }

    private enum LoadResult {
        case available([String: String])
        case unavailable
    }

    private static func cachedStore() -> [String: String]? {
        lock.lock()
        defer { lock.unlock() }
        return cachedEntries
    }

    private static func setCachedStore(_ store: [String: String]?) {
        lock.lock()
        cachedEntries = store
        lock.unlock()
    }

    private static func loadAll() -> LoadResult {
        if let cached = cachedStore() { return .available(cached) }
        let url = fileURL
        var data: Data?
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                data = try Data(contentsOf: url)
            } catch {
                log.error("Failed to read secrets.dat: \(error.localizedDescription, privacy: .public)")
                return .unavailable
            }
        }
        if let data {
            switch SecretsPayload.fileState(byteCount: data.count) {
            case .empty: log.error("secrets.dat is empty (0 bytes); treating as no file")
            case .truncated: log.error("secrets.dat is truncated (\(data.count) bytes); quarantining it")
            case .sealed: break
            }
        }
        var store: [String: String] = [:]
        // All branching lives in the pure `SecretsLoadDecision`; this function only supplies the side effects and
        // acts on the outcome. The marker is flushed before the file is moved aside, and a failed flush or move
        // yields `.unavailable`, never an empty available store.
        let outcome = SecretsLoadDecision.decide(
            byteCount: data?.count,
            decrypt: {
                guard let data else { return .undecryptable }
                let key: SymmetricKey
                do {
                    key = try symmetricKey()
                } catch {
                    log.error("Failed to derive secrets key: \(error.localizedDescription, privacy: .public)")
                    return .keyUnavailable
                }
                if let decrypted = decrypt(data, using: key) {
                    store = decrypted
                    setCachedStore(decrypted)
                    return .decrypted
                }
                // Legacy migration: files written before the HKDF/salt scheme.
                if let legacy = decrypt(data, using: legacySymmetricKey()) {
                    log.info("Migrating secrets.dat from legacy key scheme")
                    if !saveAll(legacy) {
                        log.error("Failed to re-save migrated secrets.dat")
                    }
                    store = legacy
                    return .decrypted
                }
                return .undecryptable
            },
            machineKeyIsFresh: {
                // A freshly generated machine.key can never match an existing file; don't destroy it.
                lock.lock()
                let fresh = machineKeyWasFreshlyGenerated
                lock.unlock()
                if fresh {
                    log.error("secrets.dat can't be decrypted: machine identifier unavailable (fresh fallback key)")
                }
                return fresh
            },
            markQuarantineDurably: {
                let ok = markQuarantineDurably()
                if !ok {
                    log.error("Could not persist the quarantine marker; leaving the unreadable secrets.dat in place for this launch")
                }
                return ok
            },
            moveAside: { quarantineUnreadableFile(at: url) }
        )
        switch outcome {
        case .emptyStore, .quarantinedAndReset: return .available([:])
        case .loaded: return .available(store)
        case .unavailable: return .unavailable
        }
    }

    private static func decrypt(_ data: Data, using key: SymmetricKey) -> [String: String]? {
        do {
            let box = try AES.GCM.SealedBox(combined: data)
            let plaintext = try AES.GCM.open(box, using: key)
            return SecretsPayload.decode(plaintext)
        } catch {
            return nil
        }
    }

    private static func quarantineUnreadableFile(at url: URL) -> Bool {
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = url.deletingLastPathComponent().appendingPathComponent("secrets.dat.bak-\(stamp)")
        do {
            try FileManager.default.moveItem(at: url, to: backup)
            log.error("secrets.dat could not be read; moved to \(backup.lastPathComponent, privacy: .public)")
        } catch {
            log.error("Failed to move unreadable secrets.dat aside: \(error.localizedDescription, privacy: .public)")
            return false
        }
        let defaults = UserDefaults.standard
        for name in defaults.dictionaryRepresentation().keys where name.hasPrefix(flagPrefix) {
            defaults.removeObject(forKey: name)
        }
        return true
    }

    private static func saveAll(_ store: [String: String]) -> Bool {
        do {
            let plaintext = try SecretsPayload.encode(store)
            let sealed = try AES.GCM.seal(plaintext, using: try symmetricKey())
            guard let combined = sealed.combined else { return false }
            try writeAtomically(combined, to: fileURL)
            setCachedStore(store)
            return true
        } catch {
            log.error("Encrypt failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
