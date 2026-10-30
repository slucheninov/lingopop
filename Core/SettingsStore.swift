import Foundation
import Combine
import os

@MainActor
final class SettingsStore: ObservableObject {

    /// Per-provider connection settings. Stored in the encrypted local `secrets.dat`, not in UserDefaults.
    typealias ProviderSettings = ProviderConnectionSettings

    private struct Persisted: Codable {
        var activeProvider: ProviderType
        /// Provider-keyed maps use `ProviderKeyedDictionary` (JSON object keyed by `ProviderType.rawValue`;
        /// the legacy flat-array form is still decoded).
        var fallbacks: ProviderKeyedDictionary<ProviderType>?
        var targetLanguage: String
        /// Legacy location of the per-provider settings (v0.3.19 and older). Read once to migrate them into
        /// `secrets.dat`; an empty map once the secure store holds the data (older builds require the key), only the real (legacy or user-edited) entries while the secure store is unavailable (so nothing is lost; generated defaults are never written).
        var providers: ProviderKeyedDictionary<ProviderSettings>?
        /// Only written together with a non-empty legacy `providers` map while the secure store is untrusted: per provider,
        /// the fields of that entry which are real user data (the rest is filler). Absent = the whole entry is real.
        var providerOverrideFields: ProviderKeyedDictionary<[String]>?
        var hotkey: HotkeyConfig?
        var hotkeys: [AIOperation: HotkeyConfig]?
        var launchAtLogin: Bool?
        var maxInputChars: Int?
        var maxHistoryCount: Int?
        var menuHistoryCount: Int?
        var useAutoDetect: Bool?
        var languagePairs: [String: String]?
        var iCloudSync: Bool?
        var syncHistoryToiCloud: Bool?
        var autoCopyOCR: Bool?
        var magicPrompt: String?
    }

    static let autoLanguageSentinel = "Auto"

    private let defaultsKey = "LingoPop.settings.v1"
    private let defaults: UserDefaults

    @Published var activeProvider: ProviderType
    @Published var fallbacks: [ProviderType: ProviderType]
    @Published var targetLanguage: String
    @Published var providers: [ProviderType: ProviderSettings]
    @Published var hotkeys: [AIOperation: HotkeyConfig]
    @Published var launchAtLogin: Bool
    @Published var maxInputChars: Int
    @Published var maxHistoryCount: Int
    @Published var menuHistoryCount: Int
    @Published var useAutoDetect: Bool
    @Published var languagePairs: [String: String]
    @Published var iCloudSync: Bool
    @Published var syncHistoryToiCloud: Bool
    @Published var autoCopyOCR: Bool
    @Published var magicPrompt: String
    @Published var apiKeySaveError: String? = nil
    /// Bumped whenever an API key is set or cleared so views can refresh "Key set" indicators.
    /// Intentionally not persisted and not part of auto-save.
    @Published private(set) var secretsRevision: Int = 0

    private var saveSubscription: AnyCancellable?
    private var providersSubscription: AnyCancellable?
    /// True once `secrets.dat` is known to hold the provider settings; the UserDefaults copy is then omitted.
    /// While false (secure store unreadable or a write failed) `save()` keeps writing the legacy copy.
    private var providersInSecureStore = false
    /// Real user data (legacy map entries and edits) that must win over `secrets.dat` until it is trusted again.
    /// Generated defaults are never in here, so they are never written to UserDefaults or into `secrets.dat`.
    private var providerOverrides = ProviderOverrides()
    private let log = Logger(subsystem: "com.lingopop.app", category: "SettingsStore")

    static func sanitizeMagicPrompt(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.filter { ch in
            ch == "\n" || ch == "\t" || ch.asciiValue.map { $0 >= 0x20 } ?? true
        }
        if cleaned.unicodeScalars.count > 2000 {
            return String(cleaned.unicodeScalars.prefix(2000))
        }
        return cleaned
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.removeObject(forKey: defaultsKey + ".mtime") // only used by the removed iCloud settings sync
        let loaded = Self.loadInitial(defaults: defaults, defaultsKey: defaultsKey)
        self.activeProvider = loaded.persisted.activeProvider
        self.fallbacks = loaded.persisted.fallbacks?.values ?? [:]
        self.targetLanguage = loaded.persisted.targetLanguage
        let secure = SecretStorage.loadProviderSettings()
        let overrides = ProviderOverrides(legacy: loaded.providers?.values, fieldMasks: loaded.persisted.providerOverrideFields?.values)
        let plan = ProviderSettingsMigration.plan(secure: secure, overrides: overrides)
        self.providers = plan.providers ?? Self.defaultProviders()
        if var migrated = loaded.persisted.hotkeys {
            if migrated[.translate] == nil, let legacy = loaded.persisted.hotkey {
                migrated[.translate] = legacy
            }
            self.hotkeys = migrated
        } else {
            self.hotkeys = [.translate: loaded.persisted.hotkey ?? .default]
        }
        self.launchAtLogin = loaded.persisted.launchAtLogin ?? false
        self.maxInputChars = loaded.persisted.maxInputChars ?? 5000
        self.maxHistoryCount = loaded.persisted.maxHistoryCount ?? 10
        self.menuHistoryCount = loaded.persisted.menuHistoryCount ?? 10
        self.useAutoDetect = loaded.persisted.useAutoDetect ?? false
        self.languagePairs = loaded.persisted.languagePairs ?? [
            "Russian": "Ukrainian",
            "Ukrainian": "Russian",
            "English": "Ukrainian"
        ]
        self.iCloudSync = loaded.persisted.iCloudSync ?? CloudStorage.isAvailable
        self.syncHistoryToiCloud = loaded.persisted.syncHistoryToiCloud ?? false
        self.autoCopyOCR = loaded.persisted.autoCopyOCR ?? true
        self.magicPrompt = loaded.persisted.magicPrompt ?? PromptBuilder.defaultMagicPrompt
        installAutoSave()
        installProviderPersistence()
        providerOverrides = overrides
        completeProviderMigration(plan, secure: secure)
    }

    private func installAutoSave() {
        let publishers: [AnyPublisher<Void, Never>] = [
            $activeProvider.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $fallbacks.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $targetLanguage.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $hotkeys.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $launchAtLogin.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $maxInputChars.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $maxHistoryCount.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $menuHistoryCount.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $useAutoDetect.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $languagePairs.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $iCloudSync.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $syncHistoryToiCloud.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $autoCopyOCR.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $magicPrompt.dropFirst().map { _ in () }.eraseToAnyPublisher()
        ]
        saveSubscription = Publishers.MergeMany(publishers)
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] in
                self?.save()
            }
    }

    /// Provider settings are persisted to the encrypted `secrets.dat` (debounced like the other settings),
    /// never to UserDefaults or iCloud. The decrypted copy lives in `providers`, so reads never decrypt.
    private func installProviderPersistence() {
        providersSubscription = $providers
            .dropFirst()
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.persistProviders()
            }
    }

    /// Applies the migration plan computed at init: writes the legacy provider settings into `secrets.dat`
    /// and only after that succeeded drops them from UserDefaults. On failure the old data stays untouched.
    private func completeProviderMigration(_ plan: ProviderSettingsMigration.Plan, secure: SecureProviderSettings) {
        let writeSucceeded = plan.writeSecure ? SecretStorage.saveProviderSettings(providers) : true
        let outcome = ProviderSettingsMigration.outcome(plan: plan, secure: secure, secureWriteSucceeded: writeSucceeded)
        providersInSecureStore = outcome.providersInSecureStore
        if outcome.providersInSecureStore { providerOverrides.clear() }
        switch outcome.event {
        case .none:
            break
        case .movedToSecureStore:
            log.info("Moved provider settings to secrets.dat")
        case .secureWriteFailedKeepingLegacy:
            log.error("Could not move provider settings to secrets.dat; keeping them in UserDefaults and retrying on the next change")
        }
        if outcome.mayClearLegacy {
            save() // rewrites the UserDefaults blob with an empty `providers` map
            log.info("Removed legacy provider settings from UserDefaults")
        }
    }

    private func persistProviders() {
        if providersInSecureStore {
            if SecretStorage.saveProviderSettings(providers) {
                providerOverrides.clear()
            } else {
                log.error("Failed to save provider settings to secrets.dat; keeping the edits in UserDefaults")
                providersInSecureStore = false
                save() // writes only the tracked edits as the legacy copy
            }
            return
        }
        // The secure store was not trusted: `providers` may hold generated defaults, so never write it wholesale.
        // Re-read the store and apply only the tracked overrides (real legacy data and user edits) on top of it.
        guard let merged = providerOverrides.reconciled(with: SecretStorage.loadProviderSettings()),
              SecretStorage.saveProviderSettings(merged) else {
            log.error("Not writing provider settings to secrets.dat (store unavailable, quarantined without a deliberate edit, or write failed); keeping the edits in UserDefaults")
            save()
            return
        }
        providersInSecureStore = true
        providerOverrides.clear()
        if providers != merged { providers = merged } // show what the secure store holds
        save() // empties the legacy `providers` map in UserDefaults
    }

    func save() {
        let persisted = Persisted(
            activeProvider: activeProvider,
            fallbacks: fallbacks.isEmpty ? nil : ProviderKeyedDictionary(fallbacks),
            targetLanguage: targetLanguage,
            // Never nil: an older build decodes `providers` as non-optional and would reset every setting if the
            // key were missing. While `secrets.dat` holds the data the field is an empty map, which this build ignores.
            providers: ProviderKeyedDictionary(providersInSecureStore ? [:] : providerOverrides.legacyBlobEntries),
            providerOverrideFields: providersInSecureStore ? nil : providerOverrides.fieldMasksForBlob.map { ProviderKeyedDictionary($0) },
            hotkey: hotkeys[.translate],
            hotkeys: hotkeys.isEmpty ? nil : hotkeys,
            launchAtLogin: launchAtLogin,
            maxInputChars: maxInputChars,
            maxHistoryCount: maxHistoryCount,
            menuHistoryCount: menuHistoryCount,
            useAutoDetect: useAutoDetect,
            languagePairs: languagePairs,
            iCloudSync: iCloudSync,
            syncHistoryToiCloud: syncHistoryToiCloud,
            autoCopyOCR: autoCopyOCR,
            magicPrompt: SettingsStore.sanitizeMagicPrompt(magicPrompt)
        )
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(persisted) else { return }
        defaults.set(data, forKey: defaultsKey)
        log.info("save active=\(self.activeProvider.displayName, privacy: .public) hotkeys=\(self.hotkeys.count, privacy: .public)")
    }

    func hotkey(for operation: AIOperation) -> HotkeyConfig? {
        hotkeys[operation]
    }

    func setHotkey(_ config: HotkeyConfig?, for operation: AIOperation) {
        if let config {
            hotkeys[operation] = config
        } else {
            hotkeys.removeValue(forKey: operation)
        }
    }

    func fallback(for provider: ProviderType) -> ProviderType? {
        fallbacks[provider]
    }

    func setFallback(_ value: ProviderType?, for provider: ProviderType) {
        if let value, value != provider {
            fallbacks[provider] = value
        } else {
            fallbacks.removeValue(forKey: provider)
        }
    }

    func settings(for provider: ProviderType) -> ProviderSettings {
        if let s = providers[provider] { return s }
        if let s = Self.defaultProviders()[provider] { return s }
        return ProviderSettings(baseURL: "", model: "")
    }

    func updateSettings(_ settings: ProviderSettings, for provider: ProviderType) {
        providerOverrides.recordEdit(settings, comparedTo: self.settings(for: provider), for: provider)
        providers[provider] = settings
    }

    func apiKey(for provider: ProviderType) -> String {
        KeychainService.get(keychainKey(for: provider)) ?? ""
    }

    func hasApiKey(for provider: ProviderType) -> Bool {
        KeychainService.hasKey(keychainKey(for: provider))
    }

    func setApiKey(_ key: String, for provider: ProviderType) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let storageKey = keychainKey(for: provider)
        defer { secretsRevision += 1 }
        if trimmed.isEmpty {
            KeychainService.delete(storageKey)
            apiKeySaveError = nil
        } else {
            if KeychainService.set(trimmed, for: storageKey) {
                apiKeySaveError = nil
            } else {
                apiKeySaveError = String(localized: "Failed to save API key. Please try again.")
            }
        }
    }

    func config(for provider: ProviderType, overrideTargetLanguage: String? = nil) -> ProviderConfig {
        let s = settings(for: provider)
        return ProviderConfig(
            providerType: provider,
            apiKey: apiKey(for: provider),
            baseURL: s.baseURL,
            model: s.model,
            targetLanguage: overrideTargetLanguage ?? targetLanguage,
            magicPrompt: SettingsStore.sanitizeMagicPrompt(magicPrompt),
            referer: s.referer,
            region: s.region
        )
    }

    /// Uses `rawValue` (the frozen persisted identifier), never `displayName`.
    private func keychainKey(for provider: ProviderType) -> String {
        "apiKey.\(provider.rawValue)"
    }

    /// Settings are read from the local UserDefaults blob only. The iCloud `settings.json` written by older
    /// versions is neither read nor modified: only history and usage are synced via iCloud now.
    private static func loadInitial(defaults: UserDefaults, defaultsKey: String) -> (persisted: Persisted, providers: ProviderKeyedDictionary<ProviderSettings>?) {
        let persisted = loadLocal(defaults: defaults, key: defaultsKey) ?? makeDefault()
        return (persisted, persisted.providers)
    }

    private static func loadLocal(defaults: UserDefaults, key: String) -> Persisted? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Persisted.self, from: data)
    }

    /// Default per-provider settings derived from the provider implementations (single source of truth).
    /// `preferredModel` is used only if the provider actually lists it.
    private static func defaultSettings(_ provider: AIProvider, preferredModel: String? = nil, useDefaultBaseURL: Bool = true) -> ProviderSettings {
        let model = preferredModel.flatMap { provider.availableModels.contains($0) ? $0 : nil }
            ?? provider.availableModels.first
            ?? ""
        return ProviderSettings(baseURL: useDefaultBaseURL ? provider.defaultBaseURL : "", model: model)
    }

    private static func defaultProviders() -> [ProviderType: ProviderSettings] {
        [
            .claude: defaultSettings(ClaudeProvider(), preferredModel: "claude-haiku-5-5"),
            .openai: defaultSettings(OpenAIProvider(), preferredModel: "gpt-6-luna"),
            .gemini: defaultSettings(GeminiProvider(), preferredModel: "gemini-3.8-flash"),
            .grok: defaultSettings(OpenAIProvider.grok, preferredModel: "grok-4.3"),
            .googleFree: defaultSettings(GoogleFreeProvider()),
            .googleCloud: defaultSettings(GoogleCloudProvider()),
            // Empty base URL lets DeepLProvider pick free/pro by the ":fx" key suffix.
            .deepl: defaultSettings(DeepLProvider(), useDefaultBaseURL: false),
            .microsoftTranslator: defaultSettings(MicrosoftTranslatorProvider())

        ]
    }

    private static func makeDefault() -> Persisted {
        Persisted(
            activeProvider: .claude,
            fallbacks: nil,
            targetLanguage: "Ukrainian",
            providers: nil,
            providerOverrideFields: nil,
            hotkey: nil,
            launchAtLogin: nil,
            maxInputChars: nil,
            maxHistoryCount: nil,
            menuHistoryCount: nil,
            useAutoDetect: nil,
            languagePairs: nil,
            iCloudSync: nil,
            syncHistoryToiCloud: nil,
            autoCopyOCR: nil,
            magicPrompt: nil
        )
    }
}
