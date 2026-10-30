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
    case loaded([ProviderType: ProviderConnectionSettings])
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

    /// Stores provider settings into `entries`, leaving every other entry (API keys, unknown entries) untouched.
    static func setProviderSettings(_ settings: [ProviderType: ProviderConnectionSettings], in entries: inout [String: String]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Envelope(version: currentVersion, providers: ProviderKeyedDictionary(settings)))
        guard let raw = String(data: data, encoding: .utf8) else { throw CocoaError(.fileWriteInapplicableStringEncoding) }
        entries[providerSettingsEntry] = raw
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
    static func plan(secure: SecureProviderSettings, legacy rawLegacy: [ProviderType: ProviderConnectionSettings]?) -> Plan {
        let legacy = (rawLegacy?.isEmpty ?? true) ? nil : rawLegacy
        switch secure {
        case .unavailable:
            return Plan(providers: legacy, writeSecure: false, clearLegacy: false)
        case .absent:
            guard let legacy else { return Plan(providers: nil, writeSecure: false, clearLegacy: false) }
            return Plan(providers: legacy, writeSecure: true, clearLegacy: true)
        case .loaded(let stored):
            guard let legacy else { return Plan(providers: stored, writeSecure: false, clearLegacy: false) }
            let merged = stored.merging(legacy) { _, legacyValue in legacyValue }
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
        // `unavailable` is the only state in which it must not be trusted.
        return Outcome(providersInSecureStore: secure != .unavailable,
                       mayClearLegacy: plan.clearLegacy,
                       event: plan.writeSecure ? .movedToSecureStore : .none)
    }
}
