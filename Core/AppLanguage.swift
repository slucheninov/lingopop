import Foundation

/// UI language choice for the app. Stored per Mac in its own UserDefaults key
/// (never in `SettingsStore` / iCloud) and applied through `AppleLanguages`,
/// which Foundation reads when the main bundle first resolves localized strings.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case en
    case pl
    case uk
    case de

    static let defaultsKey = "LingoPop.appLanguage"
    static let appleLanguagesKey = "AppleLanguages"

    var id: String { rawValue }

    /// Language code written to `AppleLanguages`; `nil` for `.system` (follow macOS).
    var localeCode: String? {
        self == .system ? nil : rawValue
    }

    /// Native language name, shown as data (not localized) so every entry stays
    /// readable under any UI language. `nil` for `.system`, whose label is localized.
    var nativeName: String? {
        switch self {
        case .system: return nil
        case .en: return "English"
        case .pl: return "Polski"
        case .uk: return "Українська"
        case .de: return "Deutsch"
        }
    }

    /// The stored choice; a missing or unknown value means `.system`.
    static func stored(in defaults: UserDefaults = .standard) -> AppLanguage {
        defaults.string(forKey: defaultsKey).flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    /// Persists the choice and updates `AppleLanguages` so the next launch uses it.
    func save(in defaults: UserDefaults = .standard, domain: String = AppLanguage.appDomain) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
        apply(to: defaults, domain: domain)
    }

    /// Reconciles the app-domain `AppleLanguages` override with this choice.
    ///
    /// macOS keeps the per-app language picked in System Settings in that same key, so
    /// we only ever remove or replace a value we own:
    /// - explicit language: remember the pre-existing app-domain value (once, while we
    ///   do not own the override yet), then write `[code]`;
    /// - `.system` while we own the override: restore the remembered value, or remove
    ///   the key if there was none;
    /// - `.system` without ownership: do nothing.
    ///
    /// Does not touch the stored choice. Must run before the first localized lookup of
    /// a launch to take effect for that launch. Idempotent.
    func apply(to defaults: UserDefaults = .standard, domain: String = AppLanguage.appDomain) {
        let key = Self.appleLanguagesKey
        if let code = localeCode {
            if defaults.dictionary(forKey: Self.backupKey) == nil {
                let previous = Self.appDomainLanguages(in: defaults, domain: domain)
                var backup: [String: Any] = ["had": previous != nil]
                if let previous { backup["value"] = previous }
                defaults.set(backup, forKey: Self.backupKey)
            }
            let wanted = [code]
            if Self.appDomainLanguages(in: defaults, domain: domain) != wanted {
                defaults.set(wanted, forKey: key)
            }
        } else if let backup = defaults.dictionary(forKey: Self.backupKey) {
            if (backup["had"] as? Bool) == true, let value = backup["value"] as? [String] {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
            defaults.removeObject(forKey: Self.backupKey)
        }
    }

    /// Applies the stored choice.
    static func applyStored(in defaults: UserDefaults = .standard, domain: String = AppLanguage.appDomain) {
        stored(in: defaults).apply(to: defaults, domain: domain)
    }

    // MARK: - Effective language

    /// Backup of the app-domain `AppleLanguages` value that existed before we wrote our
    /// own override. Its presence means "we own the override".
    static let backupKey = "LingoPop.appLanguage.previousAppleLanguages"

    /// Bundle identifier used as the app's UserDefaults domain.
    static let appDomain = Bundle.main.bundleIdentifier ?? ""

    /// Language codes the app ships, `en` first (fallback).
    static let supportedCodes = ["en", "pl", "uk", "de"]

    /// App-domain `AppleLanguages` only (`object(forKey:)` would fall back to the
    /// global domain and the launch-argument domain).
    static func appDomainLanguages(in defaults: UserDefaults, domain: String) -> [String]? {
        defaults.persistentDomain(forName: domain)?[appleLanguagesKey] as? [String]
    }

    /// The concrete language the app resolves to for the given preference list
    /// (e.g. `["uk-UA", "en"]` -> `.uk`; nothing supported -> `.en`).
    static func resolve(preferences: [String]) -> AppLanguage {
        let matched = Bundle.preferredLocalizations(from: supportedCodes, forPreferences: preferences)
        return matched.first.flatMap(AppLanguage.init(rawValue:)).flatMap { $0 == .system ? nil : $0 } ?? .en
    }

    /// The concrete language this choice produces on the next launch.
    func effective(systemPreferences: [String]) -> AppLanguage {
        self == .system ? Self.resolve(preferences: systemPreferences) : self
    }

    /// Whether the running UI (`launchedEffective`) differs from what `choice` would
    /// produce on a fresh launch, i.e. whether the Relaunch button is needed.
    static func needsRelaunch(choice: AppLanguage, launchedEffective: AppLanguage, systemPreferences: [String]) -> Bool {
        choice.effective(systemPreferences: systemPreferences) != launchedEffective
    }

    /// Language list `.system` resolves to: the macOS per-app value we backed up (or
    /// the live app-domain value when we own nothing), else the system-wide list.
    static func systemPreferences(in defaults: UserDefaults = .standard, domain: String = AppLanguage.appDomain) -> [String] {
        if let backup = defaults.dictionary(forKey: backupKey) {
            if (backup["had"] as? Bool) == true, let value = backup["value"] as? [String] { return value }
        } else if let own = appDomainLanguages(in: defaults, domain: domain) {
            return own
        }
        let global = defaults.persistentDomain(forName: UserDefaults.globalDomain)?[appleLanguagesKey] as? [String]
        return global ?? Locale.preferredLanguages
    }

    /// The language the UI of this process actually loaded with (reflects a
    /// `-AppleLanguages` launch argument too). Computed once, right after the stored
    /// choice is applied; see `applyAtLaunch()`.
    static let launchedEffective: AppLanguage = {
        applyStored()
        return resolve(preferences: Bundle.main.preferredLocalizations)
    }()

    /// Applies the stored choice and records the effective launch language. Call first
    /// thing in `main()`, before anything resolves a localized string.
    static func applyAtLaunch() {
        _ = launchedEffective
    }
}
