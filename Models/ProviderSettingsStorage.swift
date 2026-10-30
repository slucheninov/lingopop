import Foundation

/// Per-provider connection settings (everything except the API key, which has its own entry).
/// Stored in the encrypted local `secrets.dat` (see `SecretsPayload`), never in iCloud.
struct ProviderConnectionSettings: Codable, Equatable {
    var baseURL: String
    var model: String
    var referer: String?
    var region: String?
}

/// What the secure store (`secrets.dat`) currently holds for provider settings.
enum SecureProviderSettings: Equatable {
    /// `secrets.dat` could not be read / decrypted (or the provider-settings entry is corrupt).
    /// Nothing may be overwritten or migrated while in this state.
    case unavailable
    /// `secrets.dat` is readable but has no provider-settings entry (nothing migrated yet).
    case absent
    /// `secrets.dat` could not be decrypted in this run and was moved aside (`secrets.dat.bak-*`), so the store is
    /// now empty. Unlike `.absent` this is NOT a trusted empty store: the provider settings that lived only in the
    /// quarantined file are lost from the active store, so nothing may be migrated or cleared on that basis.
    case quarantined
    case loaded([ProviderType: ProviderConnectionSettings])

    /// Whether the store may be treated as the source of truth (legacy data may be cleared once it holds the data).
    var isTrusted: Bool {
        switch self {
        case .absent, .loaded: return true
        case .unavailable, .quarantined: return false
        }
    }
}

/// Pure (de)serialization of the `secrets.dat` plaintext.
///
/// Format: a flat JSON object `[String: String]`. API keys are entries named `apiKey.<ProviderType.rawValue>`
/// (the original, key-only format). Provider settings are one extra entry named `providerSettings.v1`
/// whose value is a JSON string `{"version":1,"providers":{"<rawValue>":{...}}}`. Because the container
/// stays a flat string map, a file written by this version is still readable (and its unknown entries are
/// preserved on rewrite) by an older build, and a key-only file written by an older build is readable here.
enum SecretsPayload {
    static let providerSettingsEntry = "providerSettings.v1"
    static let currentVersion = 1

    private struct Envelope: Codable {
        var version: Int
        var providers: ProviderKeyedDictionary<ProviderConnectionSettings>
    }

    /// How an existing `secrets.dat` is treated, judged by its size alone.
    enum FileState: Equatable {
        /// Zero bytes: holds nothing to preserve, so it is equivalent to "no file" (not quarantined, no backup made).
        /// Our own writes (temp file + atomic rename) never produce it.
        case empty
        /// 1 ..< `minimumSealedSize` bytes: cannot be an AES-GCM sealed box (nonce 12 + tag 16), i.e. a damaged file.
        /// Handled exactly like an undecryptable file: quarantined, never silently overwritten.
        case truncated
        /// Large enough to be a sealed box; decryption decides whether it is readable.
        case sealed
    }

    /// AES-GCM combined representation: 12-byte nonce + 16-byte tag, with an empty ciphertext at the very least.
    static let minimumSealedSize = 28

    static func fileState(byteCount: Int) -> FileState {
        if byteCount <= 0 { return .empty }
        return byteCount < minimumSealedSize ? .truncated : .sealed
    }

    /// Decodes the plaintext of `secrets.dat`. Returns nil if it is not a flat string map.
    static func decode(_ plaintext: Data) -> [String: String]? {
        try? JSONDecoder().decode([String: String].self, from: plaintext)
    }

    static func encode(_ entries: [String: String]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(entries)
    }

    /// Reads provider settings out of decoded entries. A missing entry is `.absent`; an entry that is not
    /// valid JSON of the expected shape is `.unavailable` so callers never overwrite or migrate over it.
    static func providerSettings(in entries: [String: String]) -> SecureProviderSettings {
        guard let raw = entries[providerSettingsEntry] else { return .absent }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: Data(raw.utf8)) else {
            return .unavailable
        }
        return .loaded(envelope.providers.values)
    }

    /// Same as `providerSettings(in:)`, but a missing entry is reported as `.quarantined` (not `.absent`) while
    /// `lostToQuarantine` is set, i.e. after an undecryptable `secrets.dat` was moved aside and no deliberate provider
    /// edit has been saved since. An entry that is present always wins (`.loaded`), whatever the marker says.
    static func providerSettings(in entries: [String: String], lostToQuarantine: Bool) -> SecureProviderSettings {
        let result = providerSettings(in: entries)
        if case .absent = result, lostToQuarantine { return .quarantined }
        return result
    }

    /// Stores provider settings into `entries`, leaving every other entry (API keys, unknown entries) untouched.
    static func setProviderSettings(_ settings: [ProviderType: ProviderConnectionSettings], in entries: inout [String: String]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Envelope(version: currentVersion, providers: ProviderKeyedDictionary(settings)))
        guard let raw = String(data: data, encoding: .utf8) else { throw CocoaError(.fileWriteInapplicableStringEncoding) }
        entries[providerSettingsEntry] = raw
    }
}

/// What decrypting an existing, large-enough `secrets.dat` gave.
enum SecretsDecryptResult: Equatable {
    case decrypted
    /// Neither key scheme opens the file.
    case undecryptable
    /// The key could not even be derived (e.g. salt / machine key problems): nothing is known about the file.
    case keyUnavailable
}

/// Result of loading `secrets.dat`.
enum SecretsLoadOutcome: Equatable {
    /// No file, or a zero-byte file: a trusted empty store, nothing moved.
    case emptyStore
    /// Decrypted successfully.
    case loaded
    /// The unreadable file was moved aside behind a durable marker; the key store starts empty (keys can be re-entered).
    case quarantinedAndReset
    /// Nothing may be read or written: callers refuse writes and the original file is left untouched.
    case unavailable
}

/// The decision flow of `SecretStorage.loadAll()` for a file that exists (or not), with the side effects injected so
/// the real flow is unit-testable in the host-less target. `loadAll()` acts only on the returned outcome.
///
/// Invariants: a file is never moved aside without a durable quarantine marker (marker first, move second); if the
/// marker or the move fails the result is `.unavailable` and never an empty available store; a freshly generated
/// machine key never quarantines (it can't match an existing file, which must be preserved).
enum SecretsLoadDecision {
    /// - Parameters:
    ///   - byteCount: size of the existing file, nil if there is none.
    ///   - decrypt: tries both key schemes (only called for a file big enough to be a sealed box).
    ///   - machineKeyIsFresh: whether the machine key was generated in this run (only asked after a failed decrypt).
    ///   - markQuarantineDurably: persists the quarantine marker; false if it could not be made durable.
    ///   - moveAside: moves the file to a backup; false if that failed.
    static func decide(
        byteCount: Int?,
        decrypt: () -> SecretsDecryptResult,
        machineKeyIsFresh: () -> Bool,
        markQuarantineDurably: () -> Bool,
        moveAside: () -> Bool
    ) -> SecretsLoadOutcome {
        func quarantine() -> SecretsLoadOutcome {
            guard markQuarantineDurably() else { return .unavailable }
            guard moveAside() else { return .unavailable }
            return .quarantinedAndReset
        }
        guard let byteCount else { return .emptyStore }
        switch SecretsPayload.fileState(byteCount: byteCount) {
        case .empty:
            return .emptyStore
        case .truncated:
            return quarantine()
        case .sealed:
            switch decrypt() {
            case .decrypted: return .loaded
            case .keyUnavailable: return .unavailable
            case .undecryptable: return machineKeyIsFresh() ? .unavailable : quarantine()
            }
        }
    }
}

/// Pure decision logic for moving provider settings from the legacy UserDefaults blob into `secrets.dat`.
///
/// Invariant: the legacy copy is removed only after the secure store is known to hold the data, so a failed
/// secure write never loses anything (the caller keeps persisting the legacy copy until a write succeeds).
enum ProviderSettingsMigration {

    struct Plan: Equatable {
        /// Settings to use in memory. nil means nothing is stored anywhere: use the built-in defaults.
        var providers: [ProviderType: ProviderConnectionSettings]?
        /// Write `providers` into the secure store.
        var writeSecure: Bool
        /// Remove the legacy copy from UserDefaults once the secure store holds `providers`
        /// (immediately if `writeSecure` is false, otherwise only after that write succeeded).
        var clearLegacy: Bool
    }

    /// - Parameters:
    ///   - secure: current state of the secure store.
    ///   - legacy: provider settings found in the UserDefaults blob, nil if the blob has none.
    ///
    /// When both hold data, the legacy copy wins per provider: it can only exist alongside secure data if
    /// a later secure write failed (so it is newer) or the data was just written from it (so it is equal).
    ///
    /// An empty `legacy` map counts as "no legacy copy": while the secure store holds the data the UserDefaults blob
    /// keeps an empty `providers` field (so older builds can still decode it), which must not trigger a migration.
    static func plan(secure: SecureProviderSettings, legacy: [ProviderType: ProviderConnectionSettings]?) -> Plan {
        plan(secure: secure, overrides: ProviderOverrides(legacy: legacy))
    }

    /// Same as `plan(secure:legacy:)`, but the legacy copy may carry field masks (see `ProviderOverrides`), in which
    /// case only the masked fields override the stored entry instead of replacing it as a whole.
    static func plan(secure: SecureProviderSettings, overrides: ProviderOverrides) -> Plan {
        let hasLegacy = !overrides.isEmpty
        switch secure {
        case .unavailable, .quarantined:
            // Untrusted: keep whatever real legacy data there is, write nothing, clear nothing.
            return Plan(providers: hasLegacy ? overrides.legacyBlobEntries : nil, writeSecure: false, clearLegacy: false)
        case .absent:
            guard hasLegacy else { return Plan(providers: nil, writeSecure: false, clearLegacy: false) }
            return Plan(providers: overrides.legacyBlobEntries, writeSecure: true, clearLegacy: true)
        case .loaded(let stored):
            guard hasLegacy, let merged = overrides.reconciled(with: secure) else {
                return Plan(providers: stored, writeSecure: false, clearLegacy: false)
            }
            return Plan(providers: merged, writeSecure: merged != stored, clearLegacy: true)
        }
    }

    enum Event: Equatable {
        /// Nothing to log.
        case none
        /// Legacy settings were written to the secure store.
        case movedToSecureStore
        /// The secure write failed: the legacy copy must be kept and the failure logged.
        case secureWriteFailedKeepingLegacy
    }

    struct Outcome: Equatable {
        /// `secrets.dat` is trusted to hold the provider settings, so the UserDefaults copy may be emptied on `save()`.
        var providersInSecureStore: Bool
        /// The legacy copy may be removed from UserDefaults now.
        var mayClearLegacy: Bool
        var event: Event
    }

    /// Write-before-clear rule. `secureWriteSucceeded` is the result of writing `plan.providers` to the secure store;
    /// it is only consulted when `plan.writeSecure` is true. A failed write never permits clearing the legacy copy.
    static func outcome(plan: Plan, secure: SecureProviderSettings, secureWriteSucceeded: Bool) -> Outcome {
        if plan.writeSecure, !secureWriteSucceeded {
            return Outcome(providersInSecureStore: false, mayClearLegacy: false, event: .secureWriteFailedKeepingLegacy)
        }
        // The secure store holds the data (written now, already there, or there is nothing to store);
        // `unavailable` and `quarantined` are the states in which it must not be trusted.
        return Outcome(providersInSecureStore: secure.isTrusted,
                       mayClearLegacy: plan.clearLegacy && secure.isTrusted,
                       event: plan.writeSecure ? .movedToSecureStore : .none)
    }
}

/// One provider's real user data that must override `secrets.dat`: the fields the user actually changed (or all fields
/// for an entry that came from a real legacy map) together with the full settings they were taken from.
struct ProviderFieldOverride: Equatable {
    enum Field: String, CaseIterable, Codable {
        case baseURL, model, referer, region
    }

    var fields: Set<Field>
    var values: ProviderConnectionSettings

    static func changedFields(from old: ProviderConnectionSettings, to new: ProviderConnectionSettings) -> Set<Field> {
        var changed = Set<Field>()
        if old.baseURL != new.baseURL { changed.insert(.baseURL) }
        if old.model != new.model { changed.insert(.model) }
        if old.referer != new.referer { changed.insert(.referer) }
        if old.region != new.region { changed.insert(.region) }
        return changed
    }

    /// `base` with only the overridden fields replaced. Without a base (nothing stored) the full values are used.
    func applied(to base: ProviderConnectionSettings?) -> ProviderConnectionSettings {
        guard var result = base else { return values }
        if fields.contains(.baseURL) { result.baseURL = values.baseURL }
        if fields.contains(.model) { result.model = values.model }
        if fields.contains(.referer) { result.referer = values.referer }
        if fields.contains(.region) { result.region = values.region }
        return result
    }
}

/// Tracks which in-memory provider settings are **real user data that must override `secrets.dat`** while the secure
/// store cannot be trusted (unreadable at launch, or a write failed): entries from a real legacy UserDefaults map, plus
/// the individual **fields** the user changed since. Generated defaults, entries merely loaded from `secrets.dat` and
/// fields the user did not touch are never tracked, so they can neither be persisted as a legacy copy nor override
/// secure-store values on reconcile (the Providers tab draft is built from generated defaults when nothing is stored,
/// so a whole-entry override would wipe stored custom fields the user never touched).
struct ProviderOverrides: Equatable {
    private(set) var entries: [ProviderType: ProviderFieldOverride]

    /// - Parameters:
    ///   - legacy: the `providers` map found in the UserDefaults blob (nil or empty means none).
    ///   - fieldMasks: per provider, the field names that map entry really overrides (written by this build while the
    ///     secure store was untrusted). A legacy entry without a mask is a whole real entry (all fields).
    init(legacy: [ProviderType: ProviderConnectionSettings]? = nil, fieldMasks: [ProviderType: [String]]? = nil) {
        entries = [:]
        for (provider, values) in legacy ?? [:] {
            let fields: Set<ProviderFieldOverride.Field>
            if let names = fieldMasks?[provider] {
                fields = Set(names.compactMap(ProviderFieldOverride.Field.init(rawValue:)))
            } else {
                fields = Set(ProviderFieldOverride.Field.allCases)
            }
            // A mask with no known field overrides nothing: never fall back to replacing the whole entry.
            if !fields.isEmpty { entries[provider] = ProviderFieldOverride(fields: fields, values: values) }
        }
    }

    var isEmpty: Bool { entries.isEmpty }

    /// Records a user edit. Only fields whose value differs from `previous` (the settings the draft was built from)
    /// are tracked; an edit that changes nothing tracks nothing.
    mutating func recordEdit(_ incoming: ProviderConnectionSettings, comparedTo previous: ProviderConnectionSettings, for provider: ProviderType) {
        let changed = ProviderFieldOverride.changedFields(from: previous, to: incoming)
        guard !changed.isEmpty else { return }
        let existing = entries[provider]?.fields ?? []
        entries[provider] = ProviderFieldOverride(fields: existing.union(changed), values: incoming)
    }

    /// Call once the secure store holds everything (after a successful write).
    mutating func clear() {
        entries = [:]
    }

    /// What to write into the UserDefaults `providers` field while the secure store is not trusted.
    /// Only real data, never generated defaults (for a field-level entry the untouched fields are filler).
    var legacyBlobEntries: [ProviderType: ProviderConnectionSettings] { entries.mapValues(\.values) }

    /// Field masks to persist next to `legacyBlobEntries` (only for entries that do not override every field).
    var fieldMasksForBlob: [ProviderType: [String]]? {
        let partial = entries.filter { $0.value.fields.count < ProviderFieldOverride.Field.allCases.count }
        guard !partial.isEmpty else { return nil }
        return partial.mapValues { $0.fields.map(\.rawValue).sorted() }
    }

    /// The map to write to the secure store once it can be read again: what it already holds with the tracked
    /// fields applied on top, field by field (never replacing a stored entry as a whole). nil if unavailable.
    func reconciled(with secure: SecureProviderSettings) -> [ProviderType: ProviderConnectionSettings]? {
        switch secure {
        case .unavailable:
            return nil
        case .quarantined:
            // The store was reset by a quarantine: only a deliberate user edit may start it again.
            return entries.isEmpty ? nil : entries.mapValues { $0.applied(to: nil) }
        case .absent:
            return entries.mapValues { $0.applied(to: nil) }
        case .loaded(let stored):
            var result = stored
            for (provider, override) in entries {
                result[provider] = override.applied(to: stored[provider])
            }
            return result
        }
    }
}
