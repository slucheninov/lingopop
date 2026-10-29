import Foundation
import Combine
import os

@MainActor
final class SettingsStore: ObservableObject {

    struct ProviderSettings: Codable, Equatable {
        var baseURL: String
        var model: String
        var referer: String?
        var region: String?
    }

    private struct Persisted: Codable {
        var activeProvider: ProviderType
        /// Provider-keyed maps use `ProviderKeyedDictionary` (JSON object keyed by `ProviderType.rawValue`;
        /// the legacy flat-array form is still decoded).
        var fallbacks: ProviderKeyedDictionary<ProviderType>?
        var targetLanguage: String
        var providers: ProviderKeyedDictionary<ProviderSettings>
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
    private let cloudFileName = "settings.json"
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
    private var pollTimer: Timer?
    private var lastCloudMTime: Date?
    private var suppressAutoSaveBefore: Date = .distantPast
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
        let loaded = Self.loadInitial(defaults: defaults, defaultsKey: defaultsKey, cloudFileName: "settings.json")
        self.activeProvider = loaded.persisted.activeProvider
        self.fallbacks = loaded.persisted.fallbacks?.values ?? [:]
        self.targetLanguage = loaded.persisted.targetLanguage
        self.providers = loaded.persisted.providers.values
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
        self.lastCloudMTime = loaded.cloudMTime
        installAutoSave()
        installCloudPolling()
    }

    private func installAutoSave() {
        let publishers: [AnyPublisher<Void, Never>] = [
            $activeProvider.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $fallbacks.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $targetLanguage.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $providers.dropFirst().map { _ in () }.eraseToAnyPublisher(),
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
                guard let self, Date() > self.suppressAutoSaveBefore else { return }
                self.save()
            }
    }

    deinit {
        pollTimer?.invalidate()
    }

    private func installCloudPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reloadFromCloudIfNewer() }
        }
    }

    func reloadFromCloudIfNewer() {
        guard iCloudSync, CloudStorage.isAvailable else { return }
        guard let cloudMTime = CloudStorage.modificationDate(cloudFileName) else { return }
        if let last = lastCloudMTime, cloudMTime <= last { return }
        guard let read = CloudStorage.read(cloudFileName),
              let decoded = try? JSONDecoder().decode(Persisted.self, from: read.data) else { return }
        apply(decoded)
        lastCloudMTime = read.modified
    }

    private func apply(_ p: Persisted) {
        suppressAutoSaveBefore = Date().addingTimeInterval(0.3)
        if activeProvider != p.activeProvider { activeProvider = p.activeProvider }
        let pf = p.fallbacks?.values ?? [:]
        if fallbacks != pf { fallbacks = pf }
        if targetLanguage != p.targetLanguage { targetLanguage = p.targetLanguage }
        if providers != p.providers.values { providers = p.providers.values }
        let pHotkeys = p.hotkeys ?? [.translate: p.hotkey ?? .default]
        if hotkeys != pHotkeys { hotkeys = pHotkeys }
        if let l = p.launchAtLogin, launchAtLogin != l { launchAtLogin = l }
        if let m = p.maxInputChars, maxInputChars != m { maxInputChars = m }
        if let m = p.maxHistoryCount, maxHistoryCount != m { maxHistoryCount = m }
        if let m = p.menuHistoryCount, menuHistoryCount != m { menuHistoryCount = m }
        if let a = p.useAutoDetect, useAutoDetect != a { useAutoDetect = a }
        if let pairs = p.languagePairs, languagePairs != pairs { languagePairs = pairs }
        if let s = p.iCloudSync, iCloudSync != s { iCloudSync = s }
        if let s = p.syncHistoryToiCloud, syncHistoryToiCloud != s { syncHistoryToiCloud = s }
        if let a = p.autoCopyOCR, autoCopyOCR != a { autoCopyOCR = a }
        let pm = p.magicPrompt ?? PromptBuilder.defaultMagicPrompt
        if magicPrompt != pm { magicPrompt = pm }
    }

    func save() {
        let persisted = Persisted(
            activeProvider: activeProvider,
            fallbacks: fallbacks.isEmpty ? nil : ProviderKeyedDictionary(fallbacks),
            targetLanguage: targetLanguage,
            providers: ProviderKeyedDictionary(providers),
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
        defaults.set(Date(), forKey: defaultsKey + ".mtime")
        log.info("save active=\(self.activeProvider.displayName, privacy: .public) hotkeys=\(self.hotkeys.count, privacy: .public)")
        if iCloudSync, CloudStorage.isAvailable {
            if let mtime = CloudStorage.write(cloudFileName, data: data) {
                lastCloudMTime = mtime
            }
        }
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
        if let s = Self.makeDefault().providers.values[provider] { return s }
        return ProviderSettings(baseURL: "", model: "")
    }

    func updateSettings(_ settings: ProviderSettings, for provider: ProviderType) {
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

    private static func loadInitial(defaults: UserDefaults, defaultsKey: String, cloudFileName: String) -> (persisted: Persisted, cloudMTime: Date?) {
        let local = loadLocal(defaults: defaults, key: defaultsKey)
        let localMTime = defaults.object(forKey: defaultsKey + ".mtime") as? Date

        if let read = CloudStorage.read(cloudFileName),
           let decoded = try? JSONDecoder().decode(Persisted.self, from: read.data) {
            if let local, let lm = localMTime, lm > read.modified {
                return (local, read.modified)
            }
            return (decoded, read.modified)
        }
        return (local ?? makeDefault(), nil)
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

    private static func makeDefault() -> Persisted {
        Persisted(
            activeProvider: .claude,
            fallbacks: nil,
            targetLanguage: "Ukrainian",
            providers: ProviderKeyedDictionary([
                .claude: defaultSettings(ClaudeProvider(), preferredModel: "claude-haiku-5-5"),
                .openai: defaultSettings(OpenAIProvider(), preferredModel: "gpt-6-luna"),
                .gemini: defaultSettings(GeminiProvider(), preferredModel: "gemini-3.8-flash"),
                .grok: defaultSettings(OpenAIProvider.grok, preferredModel: "grok-4.3"),
                .googleFree: defaultSettings(GoogleFreeProvider()),
                .googleCloud: defaultSettings(GoogleCloudProvider()),
                // Empty base URL lets DeepLProvider pick free/pro by the ":fx" key suffix.
                .deepl: defaultSettings(DeepLProvider(), useDefaultBaseURL: false),
                .microsoftTranslator: defaultSettings(MicrosoftTranslatorProvider())
            ]),
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
