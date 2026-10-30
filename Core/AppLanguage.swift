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
    func save(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
        apply(to: defaults)
    }

    /// Writes (or, for `.system`, removes) the app-domain `AppleLanguages` override.
    /// Does not touch the stored choice. Must run before the first localized lookup
    /// of a launch to take effect for that launch.
    func apply(to defaults: UserDefaults = .standard) {
        if let code = localeCode {
            let wanted = [code]
            if defaults.stringArray(forKey: Self.appleLanguagesKey) != wanted {
                defaults.set(wanted, forKey: Self.appleLanguagesKey)
            }
        } else {
            // Only removes the app-domain override; the system-wide list stays untouched.
            defaults.removeObject(forKey: Self.appleLanguagesKey)
        }
    }

    /// Applies the stored choice.
    static func applyStored(in defaults: UserDefaults = .standard) {
        stored(in: defaults).apply(to: defaults)
    }

    /// The choice in effect for this launch: read and applied once, on first access.
    /// Touch it first thing in `main()` (via `applyAtLaunch()`) so a later change in
    /// Settings can be compared against what the running UI was loaded with.
    static let launched: AppLanguage = {
        let language = stored()
        language.apply()
        return language
    }()

    static func applyAtLaunch() {
        _ = launched
    }
}
